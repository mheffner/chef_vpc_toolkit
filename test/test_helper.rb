require 'test/unit'
require 'rubygems'
require 'mocha'
CHEF_VPC_PROJECT = "#{File.dirname(__FILE__)}" unless defined?(CHEF_VPC_PROJECT)

Dir[File.join(File.dirname(__FILE__), '/../lib', '*.rb')].each do  |lib|
    require(lib)
end

require 'tempfile'
require 'fileutils'

class TmpDir

	def self.new_tmp_dir(prefix="chef-cloud-toolkit")

		tmp_file=Tempfile.new prefix
		path=tmp_file.path
		tmp_file.close(true)
		FileUtils.mkdir_p path
		return path

	end

end
