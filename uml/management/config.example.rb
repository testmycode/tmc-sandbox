
class SandboxManagerConfig < SandboxManager::BaseConfig
  # Selectively override stuff in SandboxManager::BaseConfig here
  
  # Uncomment the following to get the default network configuration
  # and autosetup. You need to run the management script as root
  # to get autoconfiguration.
  # include SandboxManager::NetworkConfig
end

