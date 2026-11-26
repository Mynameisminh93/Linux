# GoldenOS v0.2.0 — Universal Security OS (Developer Preview)

GoldenOS is an original hobby OS project. It is not macOS, Kali, Parrot OS or Tails and does not contain their proprietary code.

## Configuration
- Boot: Limine BIOS + UEFI ISO design; QEMU virtual BIOS (SeaBIOS) and UEFI (OVMF) launch profiles.
- Kernel: hybrid architecture with modular subsystem interfaces.
- GUI: native Rust renderer scaffold.
- Architectures: x86_64 first; AArch64 and RISC-V 64 are port targets, not yet bootable.
- Runtime: native execution plus planned QEMU emulation integration.
- Security: defensive monitoring, file inspection, forensics and authorized lab auditing.

## Honest implementation status
The bootstrap script in this repository generates the v0.2 source tree. This is a developer preview, not a finished universal OS.
- Included: x86_64 freestanding Rust kernel starter, Limine boot configuration, QEMU BIOS/UEFI launch scripts, Hacking terminal prototype, file signature inspection, SHA-256 hashing, native GUI interface scaffold, architecture/runtime roadmaps.
- Not included yet: full desktop, framebuffer driver, Linux ABI, full filesystem drivers, working ARM64/RISC-V ports, or bundled third-party security applications.
- No universal compatibility exists: binaries require a matching architecture, ABI, libraries and drivers.
- A physical computer needs firmware or another hardware bootstrap. QEMU can supply virtual firmware to a guest.

## Generate the source tree
On Windows 11, use WSL2 Ubuntu 24.04:

```bash
sudo apt update
sudo apt install -y build-essential clang lld llvm nasm make git qemu-system-x86 ovmf seabios xorriso mtools curl
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
bash bootstrap-goldenos-v0.2.sh
```

Then:

```bash
cd GoldenOS
chmod +x scripts/*.sh
rustup target add x86_64-unknown-none
./scripts/build-x86_64.sh
./scripts/run-qemu-bios.sh
# or:
./scripts/run-qemu-uefi.sh
```

The first kernel test uses the serial console; a blank graphical display is expected until framebuffer support is implemented.

## Hacking terminal
The prototype is a defensive local utility:
- `help`, `tools`, `inspect <file>`, `hash <file>`, `lab`
- Recognizes common file signatures; signature recognition is not complete parsing or execution.
- Lists Wireshark, Zeek, Suricata, YARA, osquery, Volatility 3, Ghidra and Nmap as external integrations; it does not silently install or execute them.
- Use security tools only on systems and networks you own or are authorized to assess.

## File formats
The inspector identifies common ELF, PE candidate, Mach-O, WebAssembly, ZIP, PNG, JPEG, PDF and ISO9660 signatures. A `.sys` suffix is not a unique format; Windows drivers are commonly PE files. GoldenOS does not load Windows kernel drivers.

## License
The project scaffold is original. Third-party tools retain their own licenses and must be reviewed individually before integration.
