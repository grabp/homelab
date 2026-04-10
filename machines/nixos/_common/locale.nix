{ vars, ... }: {
  time.timeZone = vars.timeZone;

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ALL = "en_US.UTF-8";
  };

  console.keyMap = "us";
}
