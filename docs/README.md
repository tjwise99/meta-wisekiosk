# docs

| Document | What question it answers |
|---|---|
| [`layers-and-kas.md`](layers-and-kas.md) | How does a tree of YAML and recipes become an image, for someone who has not used Yocto? |
| [`rauc-key-rotation.md`](rauc-key-rotation.md) | How do you replace the RAUC signing key the devices trust, and why must it happen in a fixed order? |
| [`issue_investigation/boot_cpu_saturation/`](issue_investigation/boot_cpu_saturation/README.md) | Across a boot, is the single core doing work, waiting on hardware, or queued behind something else? |
| [`issue_investigation/wlan0_udev_queue/`](issue_investigation/wlan0_udev_queue/README.md) | What occupies the gap between the WiFi chip appearing on the bus and `wlan0` existing, and what is removing it worth? |
| [`issue_investigation/first_boot_after_ota/`](issue_investigation/first_boot_after_ota/README.md) | What does the first boot of a freshly written slot cost, and how long is the device unreachable? |
| [`issue_investigation/wifi_instability/`](issue_investigation/wifi_instability/README.md) | Which WiFi failure hypotheses were tested and dropped, and how was the fault finally captured? |
| [`issue_investigation/netcheck_nolan_recovery/`](issue_investigation/netcheck_nolan_recovery/README.md) | Has the no-LAN good-marking withhold been seen to fire, to stay quiet, and to suppress itself? |
| [`issue_investigation/surf_memory_soak/`](issue_investigation/surf_memory_soak/README.md) | Does a fitted slope over the soak log tell you whether the browser is leaking? |
| [`issue_investigation/screenshot_capture_fbgrab/`](issue_investigation/screenshot_capture_fbgrab/README.md) | Which framebuffer capture path produces a screenshot that can be trusted as a liveness check? |
| [`issue_investigation/webkit_dependency_trims/`](issue_investigation/webkit_dependency_trims/README.md) | Can the accessibility stack be taken out of the image, from the build side or at runtime? |

Each investigation is a directory whose `README.md` carries exactly four sections in this order —
*Configuration under test*, *How the test was performed*, *Metrics*, *Changes configured as a
result* — with any raw captures as siblings beside it; match that shape when adding the next one.
