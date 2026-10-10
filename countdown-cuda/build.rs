//! Compile the CUDA kernels for this machine's GPU with nvcc

use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=kernels/solver.cu");
    println!("cargo:rerun-if-env-changed=CUDA_ARCH");
    let out = PathBuf::from(env::var("OUT_DIR").unwrap()).join("solver.fatbin");
    // Build for the installed GPU unless told otherwise so loading needs no just-in-time compilation
    let arch = env::var("CUDA_ARCH").unwrap_or_else(|_| "native".to_string());
    let status = Command::new("nvcc")
        .args(["-fatbin", "-O3", &format!("-arch={arch}"), "-o"])
        .arg(&out)
        .arg("kernels/solver.cu")
        .status()
        .expect("nvcc must be installed to build the kernels");
    assert!(status.success(), "nvcc failed");
}
