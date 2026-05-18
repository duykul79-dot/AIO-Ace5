#!/system/bin/sh
# No-op daemon stub: sleep forever with near-zero CPU.
for FD in /proc/$$/fd/*; do
  N=${FD##*/}
  case "$N" in
    0|1|2) ;;
    *[!0-9]*|'') ;;
    *) eval "exec $N<&- $N>&-" 2>/dev/null ;;
  esac
done
while true; do sleep 86400; done
