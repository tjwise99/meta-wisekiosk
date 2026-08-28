# docs

| Document | What question it answers |
|---|---|
| [`layers-and-kas.md`](layers-and-kas.md) | How does a tree of YAML and recipes become an image, for someone who has not used Yocto — and which commit is a given image from? |
| [`rauc-key-rotation.md`](rauc-key-rotation.md) | How do you replace the RAUC signing key the devices trust, and why must it happen in a fixed order? |
| [`cve-and-sbom.md`](cve-and-sbom.md) | What is the image made of, which of those packages carry published vulnerabilities, and how do you find out? |
| [`layer-currency.md`](layer-currency.md) | Has upstream moved past the commits the image's repositories are pinned to, and what does knowing that not tell you? |
| [`issue_investigation/TEMPLATE.md`](issue_investigation/TEMPLATE.md) | What shape must an issue investigation take, and what must every test run in it name? |
| [`issue_investigation/boot_cpu_saturation/`](issue_investigation/boot_cpu_saturation/README.md) | Across a boot, is the single core doing work, waiting on hardware, or queued behind something else? |
| [`issue_investigation/wlan0_udev_queue/`](issue_investigation/wlan0_udev_queue/README.md) | What occupies the gap between the WiFi chip appearing on the bus and `wlan0` existing, and what is removing it worth? |
| [`issue_investigation/first_boot_after_ota/`](issue_investigation/first_boot_after_ota/README.md) | What does the first boot of a freshly written slot cost, and how long is the device unreachable? |
| [`issue_investigation/wifi_instability/`](issue_investigation/wifi_instability/README.md) | Which WiFi failure hypotheses were tested and dropped, and how was the fault finally captured? |
| [`issue_investigation/netcheck_nolan_recovery/`](issue_investigation/netcheck_nolan_recovery/README.md) | Has the no-LAN good-marking withhold been seen to fire, to stay quiet, and to suppress itself? |
| [`issue_investigation/surf_memory_soak/`](issue_investigation/surf_memory_soak/README.md) | Does a fitted slope over the soak log tell you whether the browser is leaking? |
| [`issue_investigation/screenshot_capture_fbgrab/`](issue_investigation/screenshot_capture_fbgrab/README.md) | Which framebuffer capture path produces a screenshot that can be trusted as a liveness check? |
| [`issue_investigation/webkit_dependency_trims/`](issue_investigation/webkit_dependency_trims/README.md) | Can the accessibility stack be taken out of the image, from the build side or at runtime? |
| [`issue_investigation/clock_timesync/`](issue_investigation/clock_timesync/README.md) | Is boot-time DNS why the kiosk clock cannot be trusted — and what actually fixes it? |

Each investigation is a directory whose `README.md` is the record of record, with any raw captures
as siblings beside it. [`issue_investigation/TEMPLATE.md`](issue_investigation/TEMPLATE.md) is the
authoritative shape — copy it as the new `README.md` and fill every field. It carries three rules:

- **R1** Every test run names its board (role) and the image commit it ran.
- **R2** Every script put on a board is either shipped (link its recipe/PR) or one-off (committed in
  the investigation directory beside its `README.md`) — never left only in `local/`.
- **R3** Runs are never blended: one board × one build × one test = one run, and numbers from
  different runs never share a table.
