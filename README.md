# op5-monitor-check-nrpe-windows-disk-scanner

Queries a Windows host for drive letters by NRPE and adds a service-check for each drive letter in OP5 Monitor.

## Usage:
```
./check_nrpe_windows_disk_scanner.sh -H <op5-server> -u <op5-api-username> -p <op5-api-password> -g <Host group in OP5>
```

## Info
  * Requires plugin check_nrpe to be present
  * Runtime errors are printed to /var/tmp/windows-disk-scanner.log
