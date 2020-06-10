module ChefApply
  module Dist
    # This class is not fully implemented, depending on it is not recommended!
    # When referencing a product directly, like Chef (Now Chef Infra)
    PRODUCT = "Chef Infra Client".freeze

    # The name of the server product
    SERVER_PRODUCT = "Chef Infra Server".freeze

    # Short name for Chef Infra
    SHORT = "Chef".freeze

    # The client's alias (chef-client)
    CLIENT = "chef-client".freeze

    # name of the automate product
    AUTOMATE = "Chef Automate".freeze

    # The chef executable, as in `chef gem install` or `chef generate cookbook`
    EXEC = "chef".freeze

    # The workstation's product name
    WORKSTATION = "Chef Workstation".freeze

    # product website address
    WEBSITE = "https://chef.io".freeze

    # chef-apply's product name
    APPLY = "chef-run".freeze

    # chef-apply's executable
    APPLYEXEC = "chef-apply".freeze

    # chef-run's product name
    RUN = "Chef Run".freeze

    # chef-run executable
    RUNEXEC = "chef-run".freeze

    # Chef-Zero's product name
    ZERO = "Chef Infra Zero".freeze

    # Chef-Solo's product name
    SOLO = "Chef Infra Solo".freeze

    # The chef-zero executable (local mode)
    ZEROEXEC = "chef-zero".freeze

    # The chef-solo executable (legacy local mode)
    SOLOEXEC = "chef-solo".freeze

    # The chef-shell executable
    SHELL = "chef-shell".freeze

    # Configuration related constants
    # The chef-shell configuration file
    SHELL_CONF = "chef_shell.rb".freeze

    # The configuration directory
    CONF_DIR = "/etc/#{ChefApply::Dist::EXEC}".freeze

    # The user's configuration directory
    USER_CONF_DIR = ".chef".freeze

    # Workstation user configs
    WORKSTATION_USER_CONF_DIR = ".chef-workstation".freeze

    # The old ChefDk's product name
    DK = "ChefDK".freeze

    # The server's configuration directory
    SERVER_CONF_DIR = "/etc/chef-server".freeze

    # download.chef.io
    DOWNLOADS_URL = "downloads.chef.io".freeze

    # the "chef-workstation" in downloads.chef.io/chef-workstation/stable
    WORKSTATION_URL_SUFFIX = "chef-workstation".freeze
  end
end
