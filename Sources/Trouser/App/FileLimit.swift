import Darwin

enum FileLimit {
    @discardableResult
    static func raise(to wanted: rlim_t = rlim_t(OPEN_MAX)) -> rlim_t {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return 0 }
        guard limit.rlim_cur < wanted else { return limit.rlim_cur }
        limit.rlim_cur = min(wanted, limit.rlim_max)
        setrlimit(RLIMIT_NOFILE, &limit)
        getrlimit(RLIMIT_NOFILE, &limit)
        return limit.rlim_cur
    }
}
