REM Disable hibernation
powercfg /change -hibernate-timeout-ac 0
powercfg /change -hibernate-timeout-dc 0

REM Never turn off disks
powercfg /change -disk-timeout-ac 0
powercfg /change -disk-timeout-dc 0

REM Never turn off monitor
powercfg /change -monitor-timeout-ac 0
powercfg /change -monitor-timeout-dc 0

REM Disable sleep
powercfg /change -standby-timeout-ac 0
powercfg /change -standby-timeout-dc 0

REM Disable hibernation and sleep
powercfg /change -hibernate-timeout-ac 0 & powercfg /change -standby-timeout-ac 0
