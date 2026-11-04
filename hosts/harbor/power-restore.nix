{ pkgs, ... }:

# Power back on after AC loss, plus PL1 at Intel spec.
#
# The BIOS "Restore on AC/Power Loss" is stuck at Power Off and nobody can
# reach the BIOS (remote, headless). The BIOS reprograms the two chip registers
# behind that option at every POST, so this oneshot re-applies "power on" on
# each boot. The BIOS menu will still say "Power Off": its NVRAM setting
# (PchSetup offset 0x20) is untouched. Proper fix: in the BIOS, Advanced >
# Chipset Configuration > Restore on AC/Power Loss = Power On; then drop this.
#
# Same two registers coreboot sets from power_on_after_fail
# (soc/intel/*/pmutil.c pmc_soc_set_afterg3_en,
# superio/nuvoton/common/common.c). Setting both is deliberate: with
# CR E7[4]=0 the Super I/O passes SLP_S3# through to PSON# instead of pulsing
# the power button, and setting both avoids depending on whether the SIO's
# "always off" blocks a PCH-initiated power-on.
#
# Caveats: ~30 s unprotected window from POST until this runs. A clean
# shutdown may let the BIOS SMI handler set AG3E again, so test by pulling the
# plug while running, not "shut down, then pull the plug".
let
  script = pkgs.writeText "power-restore.py" ''
    import mmap
    import os
    import sys

    PMC_PAGE = 0xFE001000  # PWRMBASE 0xFE000000 + 0x1000, page aligned
    GEN_PMCON_A = 0x20  # byte 0; bit 0 = AG3E (1 = stay off after AC loss)
    SIO_INDEX, SIO_DATA = 0x2E, 0x2F
    RAPL = "/sys/class/powercap/intel-rapl:0/"
    PL1_UW = 125000000  # 125 W = 13600K TDP; PL2 (181 W) and tau untouched


    class Refuse(Exception):
        pass


    def pch():
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        try:
            m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED,
                          mmap.PROT_READ | mmap.PROT_WRITE, offset=PMC_PAGE)
        finally:
            os.close(fd)
        try:
            # Single-byte index access only: wider stores would hit
            # write-1-to-clear status bits in the upper bytes and GEN_PMCON_B.
            b = m[GEN_PMCON_A]
            print(f"PCH GEN_PMCON_A[7:0] before: {b:#04x} (AG3E={b & 1})")
            if b == 0xFF:
                raise Refuse("GEN_PMCON_A reads 0xff; PWRMBASE not mapped there")
            if b & 1:
                m[GEN_PMCON_A] = b & 0xFE
            a = m[GEN_PMCON_A]
            print(f"PCH GEN_PMCON_A[7:0] after:  {a:#04x} (AG3E={a & 1})")
            if a & 1:
                raise Refuse("AG3E still set after write")
        finally:
            m.close()


    def superio():
        fd = os.open("/dev/port", os.O_RDWR)

        def outb(port, v):
            os.pwrite(fd, bytes([v]), port)

        def rd(reg):
            outb(SIO_INDEX, reg)
            return os.pread(fd, 1, SIO_DATA)[0]

        def wr(reg, v):
            outb(SIO_INDEX, reg)
            outb(SIO_DATA, v)

        try:
            outb(SIO_INDEX, 0x87)  # enter config mode
            outb(SIO_INDEX, 0x87)
            chip = rd(0x20) << 8 | rd(0x21)
            if (chip & 0xFFF0) != 0xD420:
                raise Refuse(f"Super I/O ID {chip:#06x}, expected NCT6798D 0xd42x")
            wr(0x07, 0x0A)  # logical device A: ACPI
            if rd(0x07) != 0x0A:
                raise Refuse("logical device A not selected")
            e4, e7 = rd(0xE4), rd(0xE7)
            # E4[6:5]: 00 off, 01 always on, 10 last state.
            new = (e4 & ~0x60) | 0x20
            print(f"SIO CR E4 before: {e4:#04x}, CR E7: {e7:#04x}")
            # E7[4] makes the SIO pulse the power button instead: with that,
            # "on" would mean a button press while already running.
            if e7 & 0x10:
                raise Refuse("CR E7 bit 4 (EN_ONPSOUT) set; not touching E4")
            if new != e4:
                wr(0xE4, new)
            ldn, after = rd(0x07), rd(0xE4)
            print(f"SIO CR E4 after:  {after:#04x}")
            if ldn != 0x0A or after != new:
                raise Refuse(f"readback LDN {ldn:#04x} E4 {after:#04x}")
        finally:
            outb(SIO_INDEX, 0xAA)  # always leave config mode
            os.close(fd)


    def pl1():
        with open(RAPL + "constraint_0_name") as f:
            name = f.read().strip()
        if name != "long_term":
            raise Refuse(f"constraint_0 is {name!r}, expected 'long_term'")
        path = RAPL + "constraint_0_power_limit_uw"
        with open(path) as f:
            before = int(f.read())
        with open(path, "w") as f:
            f.write(str(PL1_UW))
        with open(path) as f:
            after = int(f.read())
        print(f"PL1: {before} uW -> {after} uW")
        if after != PL1_UW:
            raise Refuse("PL1 readback mismatch")


    failed = []
    # A refusal in the register part stops further register writes; PL1 is
    # independent and runs either way.
    for name, steps in (("registers", (pch, superio)), ("pl1", (pl1,))):
        try:
            for step in steps:
                step()
        except Exception as e:
            print(f"{name}: FAILED: {e}", file=sys.stderr)
            failed.append(name)
    sys.exit(f"failed: {', '.join(failed)}" if failed else 0)
  '';
in
{
  # Load RAPL with the other modules so its powercap node exists when this
  # runs (it would otherwise autoload from udev at some point).
  boot.kernelModules = [ "intel_rapl_msr" ];

  systemd.services.power-restore = {
    description = "Power on after AC loss; CPU PL1 at 125 W";
    wantedBy = [ "multi-user.target" ];
    # nct6775 probes the Super I/O config ports at module load; don't collide.
    after = [ "systemd-modules-load.service" ];
    # Needs real /dev/mem, /dev/port and CAP_SYS_RAWIO: no PrivateDevices or
    # ProtectKernel* sandboxing here.
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.python3}/bin/python3 -I -u ${script}";
    };
  };
}
