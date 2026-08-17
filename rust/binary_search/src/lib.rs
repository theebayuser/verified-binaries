mod exports;

/// Binary search over a slice sorted in nondecreasing order.
///
/// Returns the index of an element equal to `target`, or `-1` when no such
/// element exists. When `target` occurs more than once, the returned index is
/// whichever occurrence the halving lands on, not necessarily the first.
///
/// The midpoint is `lo + (hi - lo) / 2` rather than `(lo + hi) / 2` so that it
/// cannot overflow, and `hi - lo` is the loop variant the termination proof
/// uses as its measure.
pub fn binary_search(arr: &[u32], target: u32) -> i32 {
    let mut lo: usize = 0;
    let mut hi: usize = arr.len();
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        if arr[mid] < target {
            lo = mid + 1;
        } else if arr[mid] > target {
            hi = mid;
        } else {
            return mid as i32;
        }
    }
    -1
}
