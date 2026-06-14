{ inputs, ... }:
{
  imports = [ inputs.nix-amd-ai.nixosModules.default ];

  hardware.amd-npu = {
    enable = true;
    enableNPU = true; # default; set false for GPU-only hosts (see "Other hardware")
    enableFastFlowLM = true; # LLM inference on NPU (requires enableNPU)
    enableLemonade = true; # OpenAI-compatible API server
    enableROCm = true; # ROCm GPU backends (llamacpp + sd-cpp)
    enableVulkan = true; # Vulkan GPU backends (llamacpp + whispercpp)
    enableImageGen = true; # default true; set false to drop sd-cpp from closure
    lemonade.user = "lemonade"; # dedicated service account, not a login user
    lemonade.desktopApp.enable = false; # headless: just lemond API + web UI, no Tauri/Rust build
    # Bind on all interfaces, but the firewall below only opens the API port on
    # tailscale0 + the libvirt NAT bridge — default zone stays closed.
    lemonade.host = "0.0.0.0";
  };
  # BIOS already dedicates 64 GiB as GPU VRAM, so the OS sees ~64 GiB of system
  # RAM. ttm is the GTT pool the GPU borrows *on top of* that carveout, sized
  # against the remaining 64 GiB (NOT the README's 120 all-GTT preset, which
  # assumes a minimal carveout). 64 (BIOS) + 32 (GTT) ≈ 96 GiB GPU-accessible,
  # leaving ≥32 GiB for the OS.
  hardware.amd-npu.gpuMemory = {
    ttmSizeGiB = 32; # GTT spill ceiling → ttm pages_limit
    pagePoolSizeGiB = 16; # pre-cached pool   → ttm page_pool_size
  };

  users.users.burke.extraGroups = [
    "video"
    "render"
  ];

  # lemond is just an API server — it has no business running as my login user.
  # Dedicated service account: own home for ~/.cache/lemonade + downloaded model
  # weights, and video/render for GPU/NPU device access.
  users.users.lemonade = {
    isSystemUser = true;
    group = "lemonade";
    extraGroups = [
      "video"
      "render"
    ];
    home = "/var/lib/lemonade";
    createHome = true;
    description = "Lemonade AI server";
  };
  users.groups.lemonade = { };

  # Expose the lemond OpenAI-compatible API (port 13305) only over the tailnet
  # and to libvirt VMs on the NAT bridge. lemond binds 0.0.0.0; these per-iface
  # rules are what actually gates reachability (default zone denies the port).
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 13305 ];
  networking.firewall.interfaces."virbr-ocnat".allowedTCPPorts = [ 13305 ];
}
