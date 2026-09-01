# You have to change in service_restart_bash_script.sh:
SERVICE_NAME="your_service_name"
LOG_FILE="/var/log/syslog"
JOURNAL_UNIT="your_service_name"
MAX_RESTARTS=1              # Max 1 restart per hour
RESTART_COOLDOWN=3600       # 1 hour (3600 seconds) between restarts
CHECK_INTERVAL=300          # 5 minutes (300 seconds) between checks
STATE_DIR="/var/lib/your_service_name-monitor"

# Add your error patterns in service_restart_bash_script.sh:
ERROR_PATTERNS=(
    'add your error patterns'
)

# You have to change in service-monitor.service:
Description=Service_name Error Monitor
After=network.target service_name.service
Wants=service_name.service

# Before start:
chmod +x service_restart_bash_script.sh
copy service_restart_bash_script.sh to /usr/local/bin/service_restart_bash_script.sh
copy service-monitor.service to /etc/systemd/system/service-monitor.service
systemctl daemon-reload
systemctl enable service-monitor.service
systemctl start service-monitor.service
