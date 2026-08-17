/// Wasm-exported entry point for `binary_search`.
///
/// Thin `extern "C"` wrapper around the pure [`crate::binary_search`]. The
/// project convention reserves this file for the wasm ABI surface, so the
/// export table matches exactly what the verifier reasons about.
///
/// `ptr` addresses `len` consecutive `u32` values in linear memory, sorted in
/// nondecreasing order. The caller must keep `len` below `i32::MAX` so that the
/// returned index is faithful.
///
/// # Safety
///
/// `ptr` must point to `len` initialized, contiguous `u32` values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn binary_search(ptr: *const u32, len: usize, target: u32) -> i32 {
    let arr = unsafe { core::slice::from_raw_parts(ptr, len) };
    crate::binary_search(arr, target)
}
