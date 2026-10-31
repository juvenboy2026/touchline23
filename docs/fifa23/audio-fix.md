# Audio lifecycle and stereo output

Some guest audio threads have too little stack for Apple's AudioUnit lifecycle
implementation. Creating a unit already used a host thread; starting it could
still fault while the platform performed HAL and media-session work. The guest
then waited for audio buffers that no consumer released, blocking pre-match load.

`hle_audio.c` now runs create, start, stop, uninitialize and disposal through a
joined host worker with a 1 MiB stack. Calls remain synchronous to their callers.
The existing silent sink and watchdog retain queue pacing during suspension,
device failure and a started output without a consumer. `hle_oe.c` also supplies
no-op application crash-report switches, consistent with the host's absent
application-report backend, avoiding an uninitialized SDK applet interface.

FIFA can submit six-channel signed 16-bit PCM. On the tested stereo device,
passing six discrete channels lost centre dialogue and surround content. When
the game submits six channels and the AudioUnit reports a stereo device, the
host folds FL/FR plus centre and rear channels into two channels. Centre and the
corresponding rear channel use approximately -3 dB gain; LFE is omitted. Each
output saturates to int16. Queue accounting remains in guest-format bytes.

`t_audio_compat.c` exercises the actual output implementation, including centre
impulses reaching both speakers, isolated LFE omission, saturation, buffer order,
suspend/resume and watchdog recovery. Existing SPSC tests cover concurrent queue
traffic. These tests do not prove audible commentary on a particular device;
that requires a match and listening. Other layouts and multichannel devices need
separate verification. Raw audio diagnostics remain private.

User listening confirmed normal match sound and commentary on Mac; the latest
iPhone feature feedback also confirms audio and commentary. The selected language
was not independently established. See [validation](validation.md) for scope.
