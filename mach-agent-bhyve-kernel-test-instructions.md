# Mach Agent bhyve Custom-Kernel Test Instructions

## Purpose

This note tells the Mach agent exactly how to use `bhyve` to test a custom
kernel on this machine without rebooting the host and without overwriting the
guest's stock kernel.

This is the same engineering pattern GCDX used successfully for `TWQDEBUG`.
The Mach project should reuse the method, but not the GCDX-specific payloads.

## Rule 1: Do Not Test By Replacing `/boot/kernel`

Use an alternate kernel slot.

Recommended names for the Mach project:

1. kernel config: `MACHDEBUG`
2. install slot: `/boot/MACHDEBUG`
3. objdir prefix: `/tmp/machobj`
4. guest image: `/Users/me/wip-gcd-tbb-fx/vm/runs/mach-dev.img`
5. guest root mount: `/Users/me/wip-gcd-tbb-fx/vm/runs/mach-dev.root`
6. serial logs: `/Users/me/wip-gcd-tbb-fx/artifacts/mach/*.serial.log`

Reason:

1. the guest remains recoverable;
2. the stock module tree is preserved;
3. failed kernels can be replaced from the host;
4. serial logs can prove which kernel actually booted.

## Rule 2: Use Host-Side Build, Host-Side Install, Guest-Side Probe

Do not rebuild inside the guest.

The loop should be:

1. build the kernel on the host;
2. mount the guest image on the host;
3. install the custom kernel into an alternate slot in the mounted guest root;
4. copy a minimal probe and rc script into the guest root;
5. boot the guest under `bhyve`;
6. wait for a serial marker;
7. destroy the VM and parse the serial log.

That is the proven loop.

## Minimal Files To Study First

Read these local files before adapting anything:

1. [m02-bhyve-execution-progress.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/m02-bhyve-execution-progress.md)
2. [run-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/run-guest.sh)
3. [stage-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/stage-guest.sh)
4. [nextbsd-platform-rebase-onboarding.md](/Users/me/wip-gcd-tbb-fx/wip-codex54x/nextbsd-platform-rebase-onboarding.md)

Important:

1. `run-guest.sh` is generic enough to reuse almost as-is.
2. `stage-guest.sh` is GCDX-specific and stages many TWQ/dispatch/Swift
   artifacts. Do not reuse it unchanged.
3. Clone the `stage-guest.sh` pattern into a new Mach-specific script instead
   of trying to parameterize every GCDX feature away.

## Step 1: Build the Custom Kernel

Build into a dedicated objdir prefix:

```sh
env MAKEOBJDIRPREFIX=/tmp/machobj \
  make -C /usr/src buildkernel KERNCONF=MACHDEBUG -j$(sysctl -n hw.ncpu)
```

Useful linked kernel path after build:

```sh
/tmp/machobj/usr/src/amd64.amd64/sys/MACHDEBUG
```

If you only want to relink from an already-configured objdir:

```sh
env SRCTOP=/usr/src \
  make -C /tmp/machobj/usr/src/amd64.amd64/sys/MACHDEBUG kernel -j$(sysctl -n hw.ncpu)
```

Recommended debug options for early bring-up:

1. `DEBUG=-g`
2. `DDB`
3. `INVARIANTS`
4. `INVARIANT_SUPPORT`
5. `WITNESS`

## Step 2: Mount the Guest Image on the Host

If you already have a reusable guest image, attach and mount it. The key
pattern from GCDX is:

1. attach with `mdconfig`;
2. detect the `freebsd-ufs` partition with `gpart list`;
3. mount that partition at a normalized path;
4. unmount and detach using that same normalized path.

Manual pattern:

```sh
guest_img=/Users/me/wip-gcd-tbb-fx/vm/runs/mach-dev.img
guest_root=/Users/me/wip-gcd-tbb-fx/vm/runs/mach-dev.root

mkdir -p "$guest_root"
md=$(doas mdconfig -a -t vnode -f "$guest_img")
root_part=$(doas gpart list "$md" | awk '
  $2 == "Name:" { name = $3 }
  $1 == "type:" && $2 == "freebsd-ufs" { print "/dev/" name; exit }
')
doas mount "$root_part" "$guest_root"
guest_root=$(cd "$guest_root" && pwd)
```

Cleanup pattern:

```sh
doas umount "$guest_root"
doas mdconfig -d -u "${md#md}"
```

Do not skip path normalization. GCDX hit stale mount cleanup bugs when the
literal input path and the real mounted path did not match.

## Step 3: Install the Custom Kernel Into an Alternate Slot

Use FreeBSD's native `installkernel` flow with `INSTKERNNAME` and
`NO_MODULES=yes`.

Example:

```sh
env MAKEOBJDIRPREFIX=/tmp/machobj \
  make -C /usr/src installkernel \
  KERNCONF=MACHDEBUG \
  DESTDIR="$guest_root" \
  INSTKERNNAME=MACHDEBUG \
  NO_MODULES=yes
```

This should install the kernel under:

```sh
$guest_root/boot/MACHDEBUG
```

Do not install in place to `$guest_root/boot/kernel`.

## Step 4: Point the Guest Loader at the Alternate Slot

Append these lines into the mounted guest root:

```sh
printf '%s\n' 'kernel="MACHDEBUG"' \
  | doas tee -a "$guest_root/boot/loader.conf.local" >/dev/null
printf '%s\n' 'module_path="/boot/kernel;/boot/modules;/boot/MACHDEBUG"' \
  | doas tee -a "$guest_root/boot/loader.conf.local" >/dev/null
```

If the file already exists, avoid duplicate lines.

This is the exact GCDX lesson:

1. alternate kernel slot;
2. preserved stock module tree;
3. explicit loader redirect.

## Step 5: Stage a Minimal Probe

Do not start with `mach-tests`. Start with one tiny deterministic probe.

The probe should:

1. run from an rc script after normal boot;
2. emit `=== mach probe start ===`;
3. emit one JSON result line;
4. emit `=== mach probe end ===`;
5. power off the guest.

Example staging layout:

```sh
doas mkdir -p "$guest_root/root/machprobe"
doas install -m 755 ./artifacts/mach/bin/mach-probe \
  "$guest_root/root/machprobe/mach-probe"
```

Suggested first probe behavior:

1. call a harmless Mach entry point if present;
2. return controlled `ENOSYS` or `ENOTSUP` for unimplemented paths;
3. emit `EINVAL` for clearly invalid inputs.

The point is to distinguish:

1. stock guest path;
2. custom kernel path;
3. invalid call behavior.

## Step 6: Install a One-Shot rc Probe Script

Inside the mounted guest root, add a one-shot rc script such as:

```sh
$guest_root/etc/rc.d/machprobe
```

Minimal shape:

```sh
#!/bin/sh
# PROVIDE: machprobe
# REQUIRE: LOGIN
# KEYWORD: shutdown

. /etc/rc.subr

name=machprobe
start_cmd="${name}_start"
stop_cmd=":"

machprobe_start()
{
  echo '=== mach probe start ==='
  date -u
  /root/machprobe/mach-probe || true
  echo '=== mach probe end ==='
  /sbin/shutdown -p now
}

load_rc_config $name
run_rc_command "$1"
```

Then enable it:

```sh
printf '%s\n' 'machprobe_enable="YES"' \
  | doas tee -a "$guest_root/etc/rc.conf.local" >/dev/null
```

Why this shape:

1. the guest boots normally;
2. the probe is deterministic;
3. serial capture gets a stable end marker;
4. the VM powers off automatically when the probe is done.

Do not attempt PID 1 replacement or launchd boot integration at this stage.

## Step 7: Boot Under bhyve and Capture Serial Output

You can reuse the GCDX boot pattern almost directly.

Equivalent manual commands:

```sh
vm_name=mach-dev
vm_image=/Users/me/wip-gcd-tbb-fx/vm/runs/mach-dev.img
vm_memory=8G
vm_vcpus=4
serial_log=/Users/me/wip-gcd-tbb-fx/artifacts/mach/mach-$(date -u +%Y%m%dT%H%M%SZ).serial.log

doas bhyvectl --destroy --vm="$vm_name" >/dev/null 2>&1 || true
doas bhyveload -m "$vm_memory" -d "$vm_image" "$vm_name"
mkdir -p "$(dirname "$serial_log")"
set -o pipefail
doas bhyve -AHP \
  -c "$vm_vcpus" \
  -m "$vm_memory" \
  -l com1,stdio \
  -s 0,hostbridge \
  -s 31,lpc \
  -s 4:0,virtio-blk,"$vm_image" \
  "$vm_name" 2>&1 | tee "$serial_log"
status=$?
doas bhyvectl --destroy --vm="$vm_name" >/dev/null 2>&1 || true
exit "$status"
```

If you want a script, clone [run-guest.sh](/Users/me/wip-gcd-tbb-fx/wip-codex54x/scripts/bhyve/run-guest.sh)
under a Mach-specific name and only change the environment variable names if
that actually helps readability.

## Step 8: Parse the Serial Log

The host should validate only three things first:

1. the boot log proves the custom kernel booted:
   for example `FreeBSD 15.0-STABLE MACHDEBUG amd64`;
2. the probe start and end markers are both present;
3. the JSON line matches the expected stock/custom/invalid behavior.

Example checks:

```sh
grep -F 'FreeBSD 15.0-STABLE MACHDEBUG amd64' "$serial_log"
grep -F '=== mach probe start ===' "$serial_log"
grep -F '=== mach probe end ===' "$serial_log"
```

Do not call the first milestone complete if the guest boots but you cannot
prove the probe ran under the intended kernel.

## What To Reuse From GCDX

Reuse these ideas:

1. alternate kernel slot with `INSTKERNNAME`;
2. serial-first boot and logging;
3. host-side mounting and staging;
4. one-shot rc probes;
5. stock/custom control lanes;
6. automatic VM destruction after the end marker.

Do not reuse these pieces unchanged:

1. TWQ-specific syscall probes;
2. TWQ-specific sysctl assertions;
3. staged `libthr` and `libdispatch` refresh logic;
4. Swift probe staging;
5. GCDX trace env vars.

## Minimal Success Definition

The first Mach bhyve milestone is complete when:

1. a `MACHDEBUG` kernel builds on the host;
2. it installs into `/boot/MACHDEBUG` inside a mounted guest root;
3. the guest boots that kernel in `bhyve`;
4. a one-shot rc probe runs automatically;
5. the serial log proves stock vs custom vs invalid behavior clearly.

Everything after that is feature work.

## Strong Recommendation

Do not begin with full Mach semantics, `launchd`, or `notifyd`.

The first deliverable is not “Mach works”.
The first deliverable is:

> “I can boot a custom FreeBSD 15 kernel in `bhyve`, run one deterministic
> Mach probe, and prove from the serial log that I am exercising the intended
> kernel path.”

That is the same threshold GCDX had to cross before any real subsystem work
became productive.
