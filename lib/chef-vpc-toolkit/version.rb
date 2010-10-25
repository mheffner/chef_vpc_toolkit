module ChefVPCToolkit

class Version
  CHEF_VPC_TOOLKIT_ROOT = File.dirname(File.expand_path("../", File.dirname(__FILE__)))
  VERSION = IO.read(File.join(CHEF_VPC_TOOLKIT_ROOT, 'VERSION'))
end

end
