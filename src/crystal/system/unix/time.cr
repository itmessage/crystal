require "c/sys/time"
require "c/time"

{% if flag?(:darwin) %}
  # Darwin supports clock_gettime starting from macOS Sierra, but we can't
  # use it because it would prevent running binaries built on macOS Sierra
  # to run on older macOS releases.
  #
  # Furthermore, mach_absolute_time is reported to have a higher precision.
  require "c/mach/mach_time"
{% end %}

module Crystal::System::Time
  UnixEpochInSeconds = 62135596800_i64

  def self.compute_utc_seconds_and_nanoseconds : {Int64, Int32}
    {% if LibC.has_method?("clock_gettime") %}
      ret = LibC.clock_gettime(LibC::CLOCK_REALTIME, out timespec)
      raise RuntimeError.from_errno("clock_gettime") unless ret == 0
      {timespec.tv_sec.to_i64 + UnixEpochInSeconds, timespec.tv_nsec.to_i}
    {% else %}
      ret = LibC.gettimeofday(out timeval, nil)
      raise RuntimeError.from_errno("gettimeofday") unless ret == 0
      {timeval.tv_sec.to_i64 + UnixEpochInSeconds, timeval.tv_usec.to_i * 1_000}
    {% end %}
  end

  def self.monotonic : {Int64, Int32}
    {% if flag?(:darwin) %}
      info = mach_timebase_info
      total_nanoseconds = LibC.mach_absolute_time * info.numer // info.denom
      seconds = total_nanoseconds // 1_000_000_000
      nanoseconds = total_nanoseconds.remainder(1_000_000_000)
      {seconds.to_i64, nanoseconds.to_i32}
    {% else %}
      if LibC.clock_gettime(LibC::CLOCK_MONOTONIC, out tp) == 1
        raise RuntimeError.from_errno("clock_gettime(CLOCK_MONOTONIC)")
      end
      {tp.tv_sec.to_i64, tp.tv_nsec.to_i32}
    {% end %}
  end

  def self.to_timespec(time : ::Time)
    t = uninitialized LibC::Timespec
    t.tv_sec = typeof(t.tv_sec).new(time.to_unix)
    t.tv_nsec = typeof(t.tv_nsec).new(time.nanosecond)
    t
  end

  def self.to_timeval(time : ::Time)
    t = uninitialized LibC::Timeval
    t.tv_sec = typeof(t.tv_sec).new(time.to_unix)
    t.tv_usec = typeof(t.tv_usec).new(time.nanosecond // ::Time::NANOSECONDS_PER_MICROSECOND)
    t
  end

  # Many systems use /usr/share/zoneinfo, Solaris 2 has
  # /usr/share/lib/zoneinfo, IRIX 6 has /usr/lib/locale/TZ.
  ZONE_SOURCES = {
    "/usr/share/zoneinfo/",
    "/usr/share/lib/zoneinfo/",
    "/usr/lib/locale/TZ/",
  }
  LOCALTIME = "/etc/localtime"

  def self.zone_sources : Enumerable(String)
    ZONE_SOURCES
  end

  def self.load_iana_zone(iana_name : String) : ::Time::Location?
    nil
  end

  def self.load_localtime : ::Time::Location?
    if ::File.file?(LOCALTIME) && ::File.readable?(LOCALTIME)
      ::File.open(LOCALTIME) do |file|
        ::Time::Location.read_zoneinfo("Local", file)
      rescue ::Time::Location::InvalidTZDataError
        nil
      end
    end
  end

  {% if flag?(:darwin) %}
    @@mach_timebase_info : LibC::MachTimebaseInfo?

    private def self.mach_timebase_info
      @@mach_timebase_info ||= begin
        LibC.mach_timebase_info(out info)
        info
      end
    end
  {% end %}
end
