# Automated YouTube Rain Ambience Live Streaming System

A production-ready, automated live streaming system designed to stream relaxing rain ambience videos to YouTube Live continuously on a daily schedule (**8:00 PM IST to 6:00 AM IST next day - 10 hours total**).

Built using **Bash, FFmpeg, Docker, systemd/cron, and GitHub Actions**.

---

## 1. System Architecture

```
GitHub Repository (Source Code, Configuration, Workflows)
       │
       ▼ (Continuous Deployment / Synchronization)
Persistent Self-Hosted Machine / Cloud Instance (TZ=Asia/Kolkata)
       │
       ├── System Scheduler (systemd timer / cron / container loop)
       ├── Docker Service (rain-streamer)
       │     └── Supervisor (`scripts/stream.sh`)
       │           └── FFmpeg Concat Demuxer & CBR Encoder
       │                 │
       │                 ▼ (RTMPS Ingestion)
       └─────────────────► YouTube Live Endpoint
```

### Architectural Constraint (Why Self-Hosted Runner?)
GitHub-hosted Actions runners enforce a strict **6-hour limit** per job. Because this stream runs for **10 hours daily**, the streaming runtime must execute on a persistent machine (a self-hosted runner, home server, or cloud instance). GitHub Actions is used for validation, deployment, configuration updates, and manual control dispatches.

---

## 2. Directory Structure

```
rain-youtube-stream/
├── config/
│   ├── playlist.txt         # Active playlist (video paths)
│   └── stream.env.example   # Environment template
├── scripts/
│   ├── stream.sh            # Main supervisor & FFmpeg runner
│   ├── start-stream.sh      # Daemon start script
│   ├── stop-stream.sh       # Graceful stop script
│   ├── restart-stream.sh    # Restart script
│   ├── status.sh           # Formatted status viewer
│   ├── health-check.sh     # System & process health monitor
│   ├── validate-videos.sh  # Playlist & video codec validator
│   ├── normalize-video.sh   # Re-encode & audio silent track generator
│   └── generate-test-video.sh # Synthetic test video generator
├── tests/
│   ├── test_playlist.sh     # Playlist unit tests
│   ├── test_schedule.sh     # Schedule logic unit tests
│   └── test_config.sh       # Secret redaction unit tests
├── .github/
│   └── workflows/
│       ├── validate.yml     # Syntax, lint, secret scan
│       ├── deploy.yml       # Self-hosted deployment
│       └── manual-control.yml # Workflow dispatch commands
├── Dockerfile               # Production container image
├── docker-compose.yml       # Docker Compose service definition
├── .gitignore               # Git secret & log exclusion
└── README.md                # System documentation
```

---

## 3. Requirements

### Hardware Requirements
- **CPU**: 2+ cores (quad-core recommended for 1080p software encoding `libx264 -preset veryfast`).
- **RAM**: 2 GB minimum.
- **Disk**: 5 GB available storage for logs and local video library.
- **Network**: Minimum **15 Mbps upload** stable connection for 1080p30 @ 10 Mbps stream; 6 Mbps for 720p30 @ 4 Mbps.

### Software Prerequisites
- Linux OS (Ubuntu 20.04/22.04 LTS recommended) or Docker runtime.
- **FFmpeg 4.4+** & **FFprobe**.
- **Bash 4.0+**, `procps`, `curl`, `gawk`.
- Optional: `docker` and `docker-compose`.

---

## 4. YouTube Live Setup & Stream Key

1. Go to [YouTube Studio](https://studio.youtube.com).
2. Click **Create** (top right) -> **Go Live**.
3. Under **Stream**, copy:
   - **Stream URL**: `rtmps://a.rtmp.youtube.com/live2`
   - **Stream Key**: (e.g. `abcd-1234-efgh-5678`)
4. **Important**: Store the stream key safely. Never commit stream keys to Git repositories.

---

## 5. Configuration & Environment Setup

Copy the template configuration file:

```bash
cp config/stream.env.example config/stream.env
```

Edit `config/stream.env`:

```env
YOUTUBE_STREAM_URL=rtmps://a.rtmp.youtube.com/live2
YOUTUBE_STREAM_KEY=your_actual_youtube_stream_key_here

# Profiles: 1080p (10Mbps) or 720p (4Mbps)
STREAM_PROFILE=1080p
PLAYLIST_MODE=sequential
TIMEZONE=Asia/Kolkata
START_TIME=20:00
STOP_TIME=06:00
```

---

## 6. Daily Maintenance Workflows

### Scenario A: Replace an Existing Video
1. Replace `videos/rain-window.mp4` with your new video file using the exact same filename.
2. No code or `playlist.txt` changes required!

### Scenario B: Add a New Video
1. Place your new video MP4 file into `videos/` (e.g. `videos/heavy-thunder.mp4`).
2. Normalize it (if required) to match target specs:
   ```bash
   ./scripts/normalize-video.sh videos/heavy-thunder.mp4
   ```
3. Add `videos/heavy-thunder.mp4` to `config/playlist.txt`.
4. Commit & push:
   ```bash
   git add config/playlist.txt
   git commit -m "Add heavy-thunder video to playlist"
   git push origin main
   ```

---

## 7. Operational Commands

### Generate Test Videos (For initial setup/testing)
```bash
./scripts/generate-test-video.sh videos 10
```

### Validate Playlist
```bash
./scripts/validate-videos.sh
```

### Start Stream Manually
```bash
./scripts/start-stream.sh
```

To force start outside 8 PM – 6 AM IST schedule window:
```bash
./scripts/start-stream.sh --force
```

### Check Status
```bash
./scripts/status.sh
```

Example status output:
```
==========================================
Rain Stream Status
==========================================
Schedule:          20:00–06:00 Asia/Kolkata
Status:            RUNNING
Supervisor PID:    12345
FFmpeg PID:        12349
Playlist:          4 videos
Mode:              sequential
Current profile:   1080p30
Uptime:            02:15:30
==========================================
```

### Check Stream Health
```bash
./scripts/health-check.sh
```

### Stop Stream
```bash
./scripts/stop-stream.sh
```

### Restart Stream
```bash
./scripts/restart-stream.sh
```

---

## 8. Test Mode & Dry Run

### Developer Test Mode (Stream for 5 minutes immediately)
```bash
TEST_MODE=true TEST_DURATION=300 ./scripts/start-stream.sh
```

### Dry Run (Validate without streaming to YouTube)
```bash
DRY_RUN=true ./scripts/start-stream.sh --force
```

---

## 9. Automated Schedule Setup (systemd / cron)

### Option 1: systemd Timer (Recommended)

1. Create `/etc/systemd/system/rain-stream.service`:
```ini
[Unit]
Description=YouTube Rain Ambience Live Stream Service
After=network.target

[Service]
Type=forking
User=ubuntu
WorkingDirectory=/opt/rain-youtube-stream
ExecStart=/bin/bash /opt/rain-youtube-stream/scripts/start-stream.sh
ExecStop=/bin/bash /opt/rain-youtube-stream/scripts/stop-stream.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

2. Create `/etc/systemd/system/rain-stream.timer`:
```ini
[Unit]
Description=Timer for YouTube Rain Ambience Live Stream (8:00 PM IST)

[Timer]
OnCalendar=*-*-* 20:00:00 Asia/Kolkata
Persistent=true

[Install]
WantedBy=timers.target
```

3. Enable and start timer:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now rain-stream.timer
```

### Option 2: Crontab (Host crontab in Asia/Kolkata timezone)
```cron
# Start at 8:00 PM IST every day
0 20 * * * /bin/bash /opt/rain-youtube-stream/scripts/start-stream.sh >> /opt/rain-youtube-stream/logs/cron.log 2>&1

# Stop at 6:00 AM IST every day
0 6 * * * /bin/bash /opt/rain-youtube-stream/scripts/stop-stream.sh >> /opt/rain-youtube-stream/logs/cron.log 2>&1
```

---

## 10. Docker Deployment

Using Docker Compose:

```bash
# Build and launch container in background
docker-compose up -d --build

# View container status and health
docker-compose ps

# Tail container logs
docker-compose logs -f
```

---

## 11. GitHub Actions Setup & Controls

### Secrets Configuration
In your GitHub repository, navigate to **Settings -> Secrets and variables -> Actions** and add:
- `YOUTUBE_STREAM_KEY`: Your YouTube Live Stream Key.
- `YOUTUBE_STREAM_URL`: `rtmps://a.rtmp.youtube.com/live2`

### GitHub Workflows
- **`validate.yml`**: Automatically runs syntax checks, secret detection, and unit tests on every `push` and `pull_request`.
- **`deploy.yml`**: Deploys updated code and configuration to your self-hosted runner on `push` to `main`.
- **`manual-control.yml`**: Allows manually dispatching `start`, `stop`, `restart`, `status`, `health-check`, or `validate-playlist` directly from the Actions tab.

---

## 12. Troubleshooting & Security

### Key Redaction
All log outputs produced by `scripts/stream.sh` pass through a filter that redacts `YOUTUBE_STREAM_KEY` into `[REDACTED]` to prevent secret leaks in logs.

### FFmpeg Reconnection & Crash Recovery
If FFmpeg disconnects due to a transient network blip:
- The supervisor automatically retries with exponential backoff (5s, 10s, 20s, up to 60s max delay).
- Resets failure counter if the stream remains stable for > 60 seconds.
- Automatically halts when the scheduled 6:00 AM IST cutoff is reached.

---

## 13. License & Maintenance

Designed for zero-maintenance daily YouTube live streaming.
