#!/bin/bash
# ==========================================
# PART 2 (CUSTOM CODE INJECTION): Flat-manager Setup
# Base: LATEST Version (Agar tidak error TimeDelta)
# Mod: Inject Custom src/lib.rs (Agar Config terbaca + Debug)
# ==========================================
set -e

# --- CONFIGURATION ---
REPO_DIR="/srv/flatpak-repo"
DB_NAME="flatpak_repo"
DB_USER="flatmanager"
PORT=8080

# Cek config
EXISTING_DB_PASS=$(grep -oP 'postgres://[^:]+:\K[^@]+' /etc/flat-manager/config.json)
if [ -f "/etc/flat-manager/config.json" ]; then
    SECRET_KEY=$(grep -oP '"secret": "\K[^"]+' /etc/flat-manager/config.json || openssl rand -base64 24)
    DB_PASS=$EXISTING_DB_PASS
else
    DB_PASS=$(openssl rand -base64 12)
    SECRET_KEY=$(openssl rand -base64 24)
fi

if [ -z "$GPG_KEY_ID" ]; then
    read -p "Masukan GPG Key ID: " GPG_KEY_ID
fi
if [ -z "$GPG_KEY_ID" ]; then echo "❌ GPG Key ID kosong."; exit 1; fi
if [ "$EUID" -ne 0 ]; then echo "❌ Run as SUDO!"; exit 1; fi

# --- 1. INSTALL DEPENDENCIES ---
echo ">>> [1/8] Installing Dependencies..."
apt update
apt install -y postgresql libpq-dev build-essential curl pkg-config git \
    ostree libostree-dev gir1.2-ostree-1.0 \
    python3-aiohttp python3-tenacity 

# Install Rust
if ! command -v cargo &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    source "$HOME/.cargo/env"
fi

# --- 2. DATABASE ---
echo ">>> [2/8] Setting up Database..."
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || true

# --- 3. CLONE SOURCE ---
echo ">>> [3/8] Cloning Source Code (Latest)..."
rm -rf /tmp/fm-build
git clone https://github.com/flatpak/flat-manager.git /tmp/fm-build
# LOCAL_SOURCE_DIR="/home/zoanter/flat-manager"
# rsync -a --exclude 'target' --exclude '.git' "$LOCAL_SOURCE_DIR/" /tmp/fm-build/
cd /tmp/fm-build

# --- 4. INJECT CUSTOM CODE (NO FORK NEEDED) ---
echo ">>> [4/8] Injecting Custom src/lib.rs..."

# Kita timpa file lib.rs dengan kode modifikasi Anda
cat > src/lib.rs << 'EOF'
use diesel_migrations::{embed_migrations, EmbeddedMigrations, MigrationHarness};

mod api;
mod app;
mod config;
mod db;
mod delayed;
mod deltas;
pub mod errors;
mod jobs;
mod logger;
mod models;
pub mod ostree;
mod schema;
mod tokens;

use actix::prelude::*;
use actix_web::dev::Server;
use config::Config;
use deltas::{DeltaGenerator, StopDeltaGenerator};
use diesel::prelude::*;
use diesel::r2d2::{ConnectionManager, ManageConnection};
use futures3::compat::Compat;
use futures3::FutureExt;
use jobs::{JobQueue, StopJobQueue};
use log::info;
use std::env; // Added this import
use std::path;
use std::sync::Arc;
use std::time::Duration;
use tokio_signal::unix::Signal;

pub use deltas::{RemoteClientMessage, RemoteServerMessage};
pub use errors::DeltaGenerationError;

type Pool = diesel::r2d2::Pool<ConnectionManager<PgConnection>>;

// --- MODIFIED FUNCTION ---
pub fn load_config(path: &path::Path) -> Arc<Config> {
    // Check if REPO_CONFIG env variable is set
    let env_path_str = env::var("REPO_CONFIG").unwrap_or_default();
    
    // If env var exists, use it. Otherwise use the passed path argument.
    let final_path = if !env_path_str.is_empty() {
        path::Path::new(&env_path_str)
    } else {
        path
    };

    // Print debugging info to stdout
    println!(">>> DEBUG: Attempting to load config from: {:?}", final_path);
    if let Ok(abs_path) = std::fs::canonicalize(final_path) {
         println!(">>> DEBUG: Resolved absolute path: {:?}", abs_path);
    } else {
         println!(">>> DEBUG: Warning - Could not resolve absolute path (File might not exist)");
    }

    let config_data = app::load_config(final_path).unwrap_or_else(|e| {
        // Detailed panic message including the error code
        panic!("Failed to read config file {:?}. Error details: {:?}", final_path, e)
    });
    
    Arc::new(config_data)
}
// -------------------------

pub const MIGRATIONS: EmbeddedMigrations = embed_migrations!("migrations/");

fn connect_to_db(config: &Arc<Config>) -> r2d2::Pool<ConnectionManager<PgConnection>> {
    let manager = ConnectionManager::<PgConnection>::new(config.database_url.clone());
    {
        let mut conn = manager.connect().unwrap();
        log::info!("Running DB Migrations...");
        conn.run_pending_migrations(MIGRATIONS)
            .expect("Failed to run migrations");
    }

    r2d2::Pool::builder()
        .build(manager)
        .expect("Failed to create pool.")
}

fn start_delta_generator(config: &Arc<Config>) -> Addr<DeltaGenerator> {
    deltas::start_delta_generator(config.clone())
}

fn start_job_queue(
    config: &Arc<Config>,
    pool: &Pool,
    delta_generator: &Addr<DeltaGenerator>,
) -> Addr<JobQueue> {
    jobs::cleanup_started_jobs(pool).expect("Failed to cleanup started jobs");
    jobs::start_job_executor(config.clone(), delta_generator.clone(), pool.clone())
}

fn handle_signal(
    sig: i32,
    server: &Server,
    job_queue: Addr<JobQueue>,
    delta_generator: Addr<DeltaGenerator>,
) -> impl Future<Item = (), Error = std::io::Error> {
    let graceful = match sig {
        tokio_signal::unix::SIGINT => {
            info!("SIGINT received, exiting");
            false
        }
        tokio_signal::unix::SIGTERM => {
            info!("SIGTERM received, exiting");
            true
        }
        tokio_signal::unix::SIGQUIT => {
            info!("SIGQUIT received, exiting");
            false
        }
        _ => false,
    };

    info!("Stopping http server");
    server
        .stop(graceful)
        .then(move |_result| {
            info!("Stopping delta generator");
            delta_generator.send(StopDeltaGenerator())
        })
        .then(move |_result| {
            info!("Stopping job processing");
            job_queue.send(StopJobQueue())
        })
        .then(|_| {
            info!("Exiting...");
            let future = tokio::time::sleep(Duration::from_millis(300)).map(|_| {
                let result: Result<(), ()> = Ok(());
                result
            });
            Compat::new(Box::pin(future))
        })
        .then(|_| {
            System::current().stop();
            Ok(())
        })
}

fn handle_signals(
    server: Server,
    job_queue: Addr<JobQueue>,
    delta_generator: Addr<DeltaGenerator>,
) {
    let sigint = Signal::new(tokio_signal::unix::SIGINT).flatten_stream();
    let sigterm = Signal::new(tokio_signal::unix::SIGTERM).flatten_stream();
    let sigquit = Signal::new(tokio_signal::unix::SIGQUIT).flatten_stream();
    let handle_signals = sigint
        .select(sigterm)
        .select(sigquit)
        .for_each(move |sig| {
            handle_signal(sig, &server, job_queue.clone(), delta_generator.clone())
        })
        .map_err(|_| ());

    actix::spawn(handle_signals);
}

pub fn start(config: &Arc<Config>) -> Server {
    let pool = connect_to_db(config);

    let delta_generator = start_delta_generator(config);

    let job_queue = start_job_queue(config, &pool, &delta_generator);

    let app = app::create_app(pool, config, job_queue.clone(), delta_generator.clone());

    handle_signals(app.clone(), job_queue, delta_generator);

    app
}
EOF
echo "✅ Custom Code Injected Successfully."

# --- 5. COMPILING ---
echo ">>> [5/8] Compiling (With Custom Code)..."
# Compile versi terbaru (yang sudah dipatch)
cargo install --path . --bin flat-manager --bin gentoken --root /usr/local --force

echo ">>> [6/8] Installing Client..."
cp flat-manager-client /usr/local/bin/flat-manager-client
chmod +x /usr/local/bin/flat-manager-client

cd /
rm -rf /tmp/fm-build

# --- 6. CONFIG FILE ---
echo ">>> [7/8] Creating Configuration..."
mkdir -p /etc/flat-manager
if [ ! -f "/etc/flat-manager/config.json" ]; then
cat <<EOF > /etc/flat-manager/config.json
{
  "host": "0.0.0.0",
  "port": $PORT,
  "gpg-homedir": "/root/.gnupg",
  "database-url": "postgres://$DB_USER:$DB_PASS@localhost/$DB_NAME",
  "repos": {
    "stable": {
      "path": "$REPO_DIR",
      "suggested-repo-name": "my-repo",
      "gpg-key": "$GPG_KEY_ID",
      "subsets": {}
    }
  },
  "secret": "$SECRET_KEY"
}
EOF
fi
chown root:root /etc/flat-manager/config.json
chmod 644 /etc/flat-manager/config.json

# --- 7. SYSTEMD ---
echo ">>> [8/8] Configuring Systemd..."
# Kita tetap gunakan Env Var untuk keamanan ganda
cat <<EOF > /etc/systemd/system/flat-manager.service
[Unit]
Description=Flat-manager Server
After=network.target postgresql.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/flat-manager

# Dengan custom code Anda, variabel ini akan dibaca secara eksplisit
Environment="RUST_LOG=debug"
Environment="REPO_CONFIG=/etc/flat-manager/config.json"
Environment="HOME=/root"

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable flat-manager
systemctl restart flat-manager

echo ">>> Generating Admin Token..."
sleep 5
ADMIN_TOKEN=$(/usr/local/bin/gentoken \
  --secret "$SECRET_KEY" \
  --name "admin" \
  --repo "stable" \
  --scope "build" \
  --scope "publish" \
  --prefix "*")

echo ""
echo "========================================="
echo "✅ SETUP CUSTOM SELESAI"
echo "========================================="
echo "Server URL : http://$(hostname -I | cut -d' ' -f1):$PORT"
echo "Admin Token: $ADMIN_TOKEN"
echo "========================================="