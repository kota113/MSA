# AOSP product glue

The repository is intended to be checked out (or symlinked) at `vendor/msa` in an
Android 16 AOSP tree. The product inherits the official arm64 goldfish emulator product,
adds only `MsaAgent`, and does not patch framework, SurfaceFlinger, WindowManager, or
the kernel.

The agent is platform-signed because the VDM creation APIs are `@SystemApi`; the app
streaming role grants `CREATE_VIRTUAL_DEVICE` after provisioning a CDM association.
