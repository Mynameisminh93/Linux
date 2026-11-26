#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-GoldenOS}"
mkdir -p "$ROOT"/{.cargo,.vscode,boot,kernel/src,arch/{x86_64,aarch64,riscv64},runtime,filesystem/src,hacking_terminal/src,security,gui/src,scripts,docs}

cat > "$ROOT/.gitignore" <<'EOF'
build/
target/
limine/
*.iso
*.img
*.log
EOF

cat > "$ROOT/.cargo/config.toml" <<'EOF'
[build]
target = "x86_64-unknown-none"

[target.x86_64-unknown-none]
rustflags = [
  "-C", "link-arg=-Tkernel/linker.ld",
  "-C", "link-arg=--gc-sections",
  "-C", "relocation-model=static",
  "-C", "no-redzone=yes"
]
EOF

cat > "$ROOT/.vscode/extensions.json" <<'EOF'
{
  "recommendations": [
    "rust-lang.rust-analyzer",
    "ms-vscode.cpptools",
    "tamasfe.even-better-toml",
    "ms-vscode.makefile-tools"
  ]
}
EOF

cat > "$ROOT/kernel/Cargo.toml" <<'EOF'
[package]
name = "goldenos-kernel"
version = "0.2.0"
edition = "2021"

[profile.dev]
panic = "abort"

[profile.release]
panic = "abort"
codegen-units = 1
lto = true
opt-level = "s"
EOF

cat > "$ROOT/kernel/linker.ld" <<'EOF'
ENTRY(_start)
SECTIONS
{
    . = 0xffffffff80000000;
    .text : ALIGN(4K) { *(.text .text.*) }
    .rodata : ALIGN(4K) { *(.rodata .rodata.*) }
    .data : ALIGN(4K) { *(.data .data.*) }
    .bss : ALIGN(4K) { *(COMMON) *(.bss .bss.*) }
}
EOF

cat > "$ROOT/kernel/src/main.rs" <<'EOF'
#![no_std]
#![no_main]
use core::{arch::asm, panic::PanicInfo};

const COM1: u16 = 0x3F8;

#[used]
#[link_section = ".limine_requests"]
static BASE_REVISION: [u64; 3] = [0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 3];
#[used]
#[link_section = ".limine_requests_start"]
static REQUESTS_START: [u64; 2] = [0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf];
#[used]
#[link_section = ".limine_requests_end"]
static REQUESTS_END: [u64; 2] = [0xadc0e0531bb10d03, 0x9572709f31764c62];

unsafe fn outb(port: u16, value: u8) {
    asm!("out dx, al", in("dx") port, in("al") value,
         options(nomem, nostack, preserves_flags));
}
unsafe fn inb(port: u16) -> u8 {
    let value: u8;
    asm!("in al, dx", in("dx") port, out("al") value,
         options(nomem, nostack, preserves_flags));
    value
}
fn serial_init() {
    unsafe {
        outb(COM1 + 1, 0);
        outb(COM1 + 3, 0x80);
        outb(COM1, 1);
        outb(COM1 + 1, 0);
        outb(COM1 + 3, 3);
        outb(COM1 + 2, 0xC7);
        outb(COM1 + 4, 0x0B);
    }
}
fn serial_write(s: &str) {
    for b in s.bytes() {
        unsafe {
            while (inb(COM1 + 5) & 0x20) == 0 { core::hint::spin_loop(); }
            if b == b'\n' { outb(COM1, b'\r'); }
            outb(COM1, b);
        }
    }
}
#[no_mangle]
pub extern "C" fn _start() -> ! {
    serial_init();
    serial_write("\nGoldenOS v0.2.0\nArchitecture: x86_64\nBoot protocol: Limine\n");
    serial_write("Kernel: hybrid prototype\nSecurity: defensive mode\nBoot: successful\n");
    serial_write("GUI: native renderer scaffold; framebuffer driver pending\n");
    loop { unsafe { asm!("hlt", options(nomem, nostack)); } }
}
#[panic_handler]
fn panic(_: &PanicInfo) -> ! {
    serial_write("\n[KERNEL PANIC]\n");
    loop { unsafe { asm!("cli; hlt", options(nomem, nostack)); } }
}
EOF

cat > "$ROOT/kernel/src/subsystems.rs" <<'EOF'
#![no_std]
pub trait KernelSubsystem {
    fn name(&self) -> &'static str;
    fn initialize(&mut self) -> Result<(), SubsystemError>;
}
#[derive(Clone, Copy)]
pub enum SubsystemError { Unsupported, OutOfMemory, HardwareUnavailable }
EOF

cat > "$ROOT/boot/limine.conf" <<'EOF'
timeout: 3
/GoldenOS v0.2.0 (x86_64)
    protocol: limine
    path: boot():/boot/goldenos-kernel
EOF

cat > "$ROOT/filesystem/Cargo.toml" <<'EOF'
[package]
name = "goldenos-file-formats"
version = "0.2.0"
edition = "2021"
EOF

cat > "$ROOT/filesystem/src/lib.rs" <<'EOF'
pub fn identify(d: &[u8]) -> &'static str {
    if d.starts_with(b"\x7FELF") { return "ELF executable/object"; }
    if d.starts_with(b"MZ") { return "DOS/PE candidate (validate PE header)"; }
    if d.starts_with(b"\xFE\xED\xFA\xCE") || d.starts_with(b"\xFE\xED\xFA\xCF")
        || d.starts_with(b"\xCE\xFA\xED\xFE") || d.starts_with(b"\xCF\xFA\xED\xFE") { return "Mach-O"; }
    if d.starts_with(b"\0asm") { return "WebAssembly"; }
    if d.starts_with(b"PK\x03\x04") { return "ZIP"; }
    if d.starts_with(b"\x89PNG\r\n\x1A\n") { return "PNG"; }
    if d.starts_with(b"\xFF\xD8\xFF") { return "JPEG"; }
    if d.starts_with(b"%PDF-") { return "PDF"; }
    if d.len() > 0x8006 && &d[0x8001..0x8006] == b"CD001" { return "ISO9660"; }
    "Unknown signature"
}
EOF

cat > "$ROOT/hacking_terminal/Cargo.toml" <<'EOF'
[package]
name = "goldenos-hacking"
version = "0.2.0"
edition = "2021"

[dependencies]
sha2 = "0.10"
goldenos-file-formats = { path = "../filesystem" }
EOF

cat > "$ROOT/hacking_terminal/src/main.rs" <<'EOF'
use sha2::{Digest, Sha256};
use std::{env, fs, path::Path};

fn help() {
    println!("GoldenOS Hacking Terminal v0.2.0");
    println!("help | tools | inspect <file> | hash <file> | lab");
}
fn tools() {
    let rows = [
        ("Wireshark", "Packet analysis", "external integration"),
        ("Zeek", "Network monitoring", "external integration"),
        ("Suricata", "Intrusion detection", "external integration"),
        ("YARA", "File pattern classification", "external integration"),
        ("osquery", "Endpoint inventory", "external integration"),
        ("Volatility 3", "Memory forensics", "external integration"),
        ("Ghidra", "Binary analysis", "external integration"),
        ("Nmap", "Authorized asset inventory", "external; permission required"),
    ];
    for (name, purpose, status) in rows {
        println!("{name:<16} {purpose:<34} {status}");
    }
    println!("Catalogue only: this preview does not install or launch third-party tools.");
}
fn main() {
    let a: Vec<String> = env::args().collect();
    match a.get(1).map(String::as_str) {
        Some("tools") => tools(),
        Some("inspect") if a.len() > 2 => {
            let p = Path::new(&a[2]);
            match fs::read(p) {
                Ok(d) => {
                    println!("File: {}", p.display());
                    println!("Size: {} bytes", d.len());
                    println!("Format: {}", goldenos_file_formats::identify(&d));
                    if p.extension().and_then(|x| x.to_str()) == Some("sys") {
                        println!("Note: .sys is an extension, commonly PE; inspection only.");
                    }
                }
                Err(e) => { eprintln!("Read failed: {e}"); std::process::exit(1); }
            }
        }
        Some("hash") if a.len() > 2 => {
            match fs::read(&a[2]) {
                Ok(d) => println!("{:x}  {}", Sha256::digest(&d), a[2]),
                Err(e) => { eprintln!("Read failed: {e}"); std::process::exit(1); }
            }
        }
        Some("lab") => println!("Only assess systems you own or have explicit permission to test. Use isolated VMs."),
        _ => help(),
    }
}
EOF

cat > "$ROOT/gui/src/lib.rs" <<'EOF'
#![no_std]
#[derive(Clone, Copy)]
pub struct Color { pub r: u8, pub g: u8, pub b: u8, pub a: u8 }
#[derive(Clone, Copy)]
pub struct Rect { pub x: usize, pub y: usize, pub width: usize, pub height: usize }
pub trait Surface {
    fn width(&self) -> usize;
    fn height(&self) -> usize;
    fn put_pixel(&mut self, x: usize, y: usize, color: Color);
    fn fill_rect(&mut self, r: Rect, c: Color) {
        let xe = r.x.saturating_add(r.width).min(self.width());
        let ye = r.y.saturating_add(r.height).min(self.height());
        for y in r.y.min(self.height())..ye {
            for x in r.x.min(self.width())..xe { self.put_pixel(x, y, c); }
        }
    }
}
EOF

cat > "$ROOT/scripts/build-x86_64.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for x in cargo git make xorriso; do command -v "$x" >/dev/null || { echo "Missing dependency: $x"; exit 1; }; done
rustup target add x86_64-unknown-none
if [ ! -d limine ]; then git clone https://github.com/limine-bootloader/limine.git --branch=v8.x-binary --depth=1 limine; fi
make -C limine
cargo build --manifest-path kernel/Cargo.toml --release
mkdir -p build/iso_root/boot/limine
cp kernel/target/x86_64-unknown-none/release/goldenos-kernel build/iso_root/boot/goldenos-kernel
cp boot/limine.conf build/iso_root/boot/limine/limine.conf
cp limine/limine-bios.sys limine/limine-bios-cd.bin limine/limine-uefi-cd.bin limine/limine-uefi.sys build/iso_root/boot/limine/
xorriso -as mkisofs -b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table --efi-boot boot/limine/limine-uefi-cd.bin --efi-boot-part --efi-boot-image --protective-msdos-label build/iso_root -o build/GoldenOS-v0.2-x86_64.iso
if [ -x limine/limine ]; then limine/limine bios-install build/GoldenOS-v0.2-x86_64.iso || true; fi
echo "ISO: build/GoldenOS-v0.2-x86_64.iso"
EOF

cat > "$ROOT/scripts/run-qemu-bios.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ISO=build/GoldenOS-v0.2-x86_64.iso
test -f "$ISO" || { echo "Build ISO first"; exit 1; }
qemu-system-x86_64 -machine q35 -m 1536 -smp 2 -bios /usr/share/seabios/bios-256k.bin -cdrom "$ISO" -boot d -serial stdio -no-reboot -no-shutdown
EOF

cat > "$ROOT/scripts/run-qemu-uefi.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ISO=build/GoldenOS-v0.2-x86_64.iso
OVMF="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}"
test -f "$ISO" || { echo "Build ISO first"; exit 1; }
test -f "$OVMF" || { echo "OVMF not found; set OVMF_CODE"; exit 1; }
qemu-system-x86_64 -machine q35 -m 1536 -smp 2 -drive if=pflash,format=raw,readonly=on,file="$OVMF" -cdrom "$ISO" -boot d -serial stdio -no-reboot -no-shutdown
EOF

cat > "$ROOT/scripts/test-qemu-x86_64.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ISO=build/GoldenOS-v0.2-x86_64.iso
test -f "$ISO" || { echo "Build ISO first"; exit 1; }
mkdir -p build
rm -f build/qemu-serial.log
set +e
timeout 12s qemu-system-x86_64 -machine q35 -m 1536 -smp 2 -cdrom "$ISO" -boot d -display none -serial file:build/qemu-serial.log -no-reboot -no-shutdown
set -e
grep -q "Boot: successful" build/qemu-serial.log || { cat build/qemu-serial.log; echo FAIL; exit 1; }
cat build/qemu-serial.log
echo "PASS: kernel entry reached"
EOF

cat > "$ROOT/arch/README.md" <<'EOF'
# Architecture status
x86_64 is the first boot target. AArch64 and RISC-V 64 are planned ports, not bootable builds yet. Each needs architecture-specific boot, exception, paging, interrupt and driver code.
EOF
echo "GoldenOS v0.2 source tree created at: $ROOT"
echo "This is a starter scaffold; ARM64/RISC-V, full GUI, Linux ABI and complete filesystem drivers remain future work."
