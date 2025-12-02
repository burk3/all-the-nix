{
  pkgs,
  ...
}:
{
  ## powerrrrrr

  environment.systemPackages = with pkgs; [
    powertop
  ];

  # all encompasing?
  powerManagement.enable = true;

  # should hybrid-sleep this puppy when battery goes below 5%, even while it's asleep?
  services.upower.enable = true;

  # currently tuned is the bees knees.
  services.tuned.enable = true;
  services.power-profiles-daemon.enable = false;
  services.tlp.enable = false;

  # I _think_ i want wakeup on the north east and north west usb ports
  # so I stand a chance of plugging in closed to a tb dock w/ external
  # monitors, pressing an external keyboard key, and having the thing wake
  # up.
  #boot.initrd.services.udev.rules = let
  #  mkRule = (bus: ''
  #    ACTION=="add", SUBSYSTEM=="usb", KERNEL==${bus}, ATTR{power/wakeup}="enabled"'');
  #  busses = [ "usb6" "usb8" ];
  #in
  #lib.strings.concatMapStrings (bus: (mkRule bus) + "\n") busses;
}
