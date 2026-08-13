# WebKit's translation units peak around 1.0-1.3 GB of compiler RSS each. At the
# default parallelism this host ran six at once against 12 GB of RAM, swapped 22
# million pages, and drove the compilers to ~8% CPU efficiency -- one source file
# took three hours 45 minutes of wall time for 19 minutes of CPU.
#
# Two is not a throttle, it is the setting that finishes first.
PARALLEL_MAKE = "-j 2"
