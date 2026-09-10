# Embedded by BurnPlanner. Requires bash; all inputs are shell-quoted assignments.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
fail() { printf '%s\n' "$*" >&2; exit 1; }
WORK=$(mktemp -d /private/tmp/rufusmac.XXXXXXXX)
OWN_MOUNT=0
printf '%s\n' 'RM_STAGE|Checking the ISO and USB'
cleanup() {
    if [ "$OWN_MOUNT" = 1 ]; then "$HDIUTIL" detach "$WORK/iso" >/dev/null 2>&1 || true; fi
    # Never recursively delete a mountpoint, even if detaching failed.
    rmdir "$WORK/iso" 2>/dev/null || true
    rm -f "$WORK/info.plist" "$WORK/images.plist" "$WORK/differences" "$WORK/large"
    rmdir "$WORK" 2>/dev/null || true
}
trap cleanup EXIT
[ -f "$ISO" ] && [ -r "$ISO" ] || fail 'The ISO cannot be read.'

# Reuse an existing read-only mount without unmounting the user's Finder volume.
"$HDIUTIL" info -plist > "$WORK/images.plist"
ISO_MOUNT=''
i=0
while candidate=$(/usr/bin/plutil -extract "images.$i.image-path" raw -o - "$WORK/images.plist" 2>/dev/null); do
    if [ "$candidate" = "$ISO" ]; then
        j=0
        while /usr/bin/plutil -extract "images.$i.system-entities.$j" xml1 -o - "$WORK/images.plist" >/dev/null 2>&1; do
            candidate_mount=$(/usr/bin/plutil -extract "images.$i.system-entities.$j.mount-point" raw -o - "$WORK/images.plist" 2>/dev/null || true)
            if [ -n "$candidate_mount" ]; then ISO_MOUNT=$candidate_mount; break; fi
            j=$((j + 1))
        done
    fi
    [ -z "$ISO_MOUNT" ] || break
    i=$((i + 1))
done
if [ -z "$ISO_MOUNT" ]; then
    mkdir "$WORK/iso"
    "$HDIUTIL" attach -readonly -nobrowse -noverify -mountpoint "$WORK/iso" "$ISO"
    OWN_MOUNT=1
    ISO_MOUNT="$WORK/iso"
fi
"$DISKUTIL" info -plist "$ISO_MOUNT" > "$WORK/info.plist"
[ "$(/usr/bin/plutil -extract WritableVolume raw -o - "$WORK/info.plist")" = false ] || fail 'The ISO mount must be read-only.'
[ -f "$ISO_MOUNT/efi/boot/bootx64.efi" ] || [ -f "$ISO_MOUNT/efi/boot/bootaa64.efi" ] || fail 'No Windows UEFI bootloader found.'
[ -f "$ISO_MOUNT/sources/boot.wim" ] || fail 'No Windows setup image found.'
[ -f "$ISO_MOUNT/sources/install.wim" ] || [ -f "$ISO_MOUNT/sources/install.esd" ] || [ -f "$ISO_MOUNT/sources/install.swm" ] || fail 'No Windows installation payload found.'

# Discover large files from the actual mounted image, not stale UI metadata.
SPLIT=0
if [ -f "$ISO_MOUNT/sources/install.wim" ] && [ "$(/usr/bin/stat -f %z "$ISO_MOUNT/sources/install.wim")" -gt 4294967295 ]; then
    SPLIT=1
    [ -x "$WIMLIB" ] || fail 'wimlib is missing. Install it with Homebrew: brew install wimlib. USB has not been erased.'
    "$WIMLIB" --version >/dev/null
fi
/usr/bin/find "$ISO_MOUNT" -type f -size +4294967295c ! -path "$ISO_MOUNT/sources/install.wim" -print > "$WORK/large"
[ ! -s "$WORK/large" ] || fail 'A file other than install.wim exceeds FAT32 limits (large ESD is not supported). USB has not been erased.'
NEEDED=$(/usr/bin/du -sk "$ISO_MOUNT" | /usr/bin/awk '{print $1}')
[ "$((NEEDED * 1024 + 268435456))" -lt "$EXPECTED_SIZE" ] || fail 'Not enough USB space.'

# Recheck the physical target immediately before erasing; fail closed.
"$DISKUTIL" info -plist "$DISK" > "$WORK/info.plist"
get_info() { /usr/bin/plutil -extract "$1" raw -o - "$WORK/info.plist"; }
[ "$(get_info Internal)" = false ] || fail 'Refusing an internal disk.'
[ "$(get_info WholeDisk)" = true ] || fail 'Select a whole disk.'
[ "$(get_info VirtualOrPhysical)" = Physical ] || fail 'Refusing a virtual disk.'
[ "$(get_info BusProtocol)" = USB ] || fail 'Select a physical USB disk.'
[ "$(get_info TotalSize)" = "$EXPECTED_SIZE" ] || fail 'USB changed size. Select it again.'
[ "$(get_info MediaName)" = "$EXPECTED_NAME" ] || fail 'USB changed identity. Select it again.'
[ "$(get_info DeviceNode)" = "$DISK" ] || fail 'USB identifier changed.'
[ "$(get_info Writable)" = true ] || fail 'USB is read-only.'
printf '%s\n' 'RM_STAGE|Formatting the USB — administrator approval may be needed'
# Keep ISO access, mounting, wimlib, and copying in the user's process.
# Elevate only the system formatting command. Injected fixture tools run directly.
if [ "$DISKUTIL" = /usr/sbin/diskutil ]; then
    format_script=$(cat <<'ROOTSCRIPT'
set -euo pipefail
info=$(/usr/sbin/diskutil info -plist "$3")
field() { printf '%s' "$info" | /usr/bin/plutil -extract "$1" raw -o - -; }
[ "$(field Internal)" = false ] && [ "$(field WholeDisk)" = true ] &&
[ "$(field VirtualOrPhysical)" = Physical ] && [ "$(field BusProtocol)" = USB ] &&
[ "$(field TotalSize)" = "$4" ] && [ "$(field MediaName)" = "$5" ] &&
[ "$(field DeviceNode)" = "$3" ] && [ "$(field Writable)" = true ] || {
    printf '%s\n' 'USB changed while authorizing. Select it again.' >&2; exit 1;
}
/usr/sbin/diskutil eraseDisk 'MS-DOS FAT32' "$1" "$2" "$3"
ROOTSCRIPT
)
    /usr/bin/osascript - "$format_script" "$LABEL" "$SCHEME" "$DISK" "$EXPECTED_SIZE" "$EXPECTED_NAME" <<'APPLESCRIPT'
on run argv
    set formatCommand to "/bin/bash -c " & quoted form of (item 1 of argv) & " --"
    repeat with i from 2 to count of argv
        set formatCommand to formatCommand & " " & quoted form of (item i of argv)
    end repeat
    do shell script formatCommand with prompt "Macus needs to format the selected USB drive." with administrator privileges
end run
APPLESCRIPT
else
    "$DISKUTIL" eraseDisk 'MS-DOS FAT32' "$LABEL" "$SCHEME" "$DISK"
fi
# GPT creates an EFI partition at s1; the data partition is s2.
SLICE="${DISK}s1"
[ "$SCHEME" != GPT ] || SLICE="${DISK}s2"
VOL=$("$DISKUTIL" info -plist "$SLICE" | /usr/bin/plutil -extract MountPoint raw -o - -)
[ -n "$VOL" ] && [ -d "$VOL" ] || fail 'The new USB volume is not mounted.'
printf '%s\n' 'RM_STAGE|Copying Windows setup files'
# Avoid Unix ownership/permission preservation on FAT32.
if [ "$SPLIT" = 1 ]; then
    "$RSYNC" -r --progress --exclude=/sources/install.wim "$ISO_MOUNT/" "$VOL/"
    printf '%s\n' 'RM_STAGE|Splitting the large Windows image'
    "$WIMLIB" split "$ISO_MOUNT/sources/install.wim" "$VOL/sources/install.swm" 3800 --check
else
    "$RSYNC" -r --progress "$ISO_MOUNT/" "$VOL/"
fi
if [ "$VERIFY" = 1 ]; then
    printf '%s\n' 'RM_STAGE|Verifying copied files'
    /usr/bin/find "$ISO_MOUNT" -type f -print0 | while IFS= read -r -d '' source_file; do
        relative=${source_file#"$ISO_MOUNT/"}
        if [ "$SPLIT" = 1 ] && [ "$relative" = sources/install.wim ]; then continue; fi
        /usr/bin/cmp -s "$source_file" "$VOL/$relative" || fail "Verification failed: $relative differs from the ISO."
    done
    if [ "$SPLIT" = 1 ]; then
        "$WIMLIB" verify "$VOL/sources/install.swm" --ref="$VOL/sources/install*.swm"
    fi
fi
