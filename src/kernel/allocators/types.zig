pub const MemoryBlock = struct {
    addr: usize,
    size: usize,
};

pub const UsageReport = struct {
    free: usize,
    reserved: usize,
    used: usize,
};
