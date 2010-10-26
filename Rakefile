require 'rake/testtask'

CHEF_VPC_PROJECT = "#{File.dirname(__FILE__)}" unless defined?(CHEF_VPC_PROJECT)

$:.unshift File.join(File.dirname(__FILE__),'lib')
require 'chef-vpc-toolkit'
include ChefVPCToolkit

Dir[File.join(File.dirname(__FILE__), 'rake', '*.rake')].each do  |rakefile|
	import(rakefile)
end

Rake::TestTask.new(:test) do |t|
	t.pattern = 'test/*_test.rb'
	t.verbose = true
end
Rake::Task['test'].comment = "Unit"

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
	gemspec.name = "chef-vpc-toolkit"
	gemspec.summary = "Rake tasks to automate and configure server groups in the cloud with Chef."
	gemspec.description = "The Chef VPC Toolkit is a set of Rake tasks that provide a framework to help automate the creation and configuration of cloud server groups for development or testing. Requires Cloud Servers VPC."
	gemspec.email = "dan.prince@rackspace.com"
	gemspec.homepage = "http://github.com/rackspace/chef-vpc-toolkit"
	gemspec.authors = ["Dan Prince"]
    gemspec.add_dependency 'rake'
    gemspec.add_dependency 'builder'
    gemspec.add_dependency 'json'
  end
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install jeweler"
end
