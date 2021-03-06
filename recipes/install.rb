#
# Cookbook Name:: mesos
# Recipe:: install
#
# Copyright (C) 2015 Medidata Solutions, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'chef-sugar'
include_recipe 'java::default'

distro = node['platform']

directory '/etc/mesos-chef'

# Configure package repositories
include_recipe 'mesos::repo'

case distro
when 'debian', 'ubuntu'
  %w( unzip default-jre-headless libcurl3 libsvn1).each do |pkg|
    package pkg do
      action :install
    end
  end

  package 'mesos' do
    action :install
    # --no-install-recommends to skip installing zk. unnecessary.
    options '--no-install-recommends'
    # Glob is necessary to select the deb version string
    version "#{node['mesos']['version']}*"
  end
when 'rhel', 'redhat', 'centos', 'amazon', 'scientific'
  compile_time do
    package 'yum-utils'
  end

  %w( unzip libcurl subversion ).each do |pkg|
    yum_package pkg do
      action :install
    end
  end

  yum_package 'jdk' do
    action :purge
  end

  execute 'update java alternatives' do
    command '/usr/sbin/alternatives --auto java'
    action :run
  end

  execute 'ldconfig' do
    command '/sbin/ldconfig'
    action :nothing
  end

  file '/etc/ld.so.conf.d/jre.conf' do
    content "#{node['java']['java_home']}/jre/lib/amd64/server"
    notifies :run, 'execute[ldconfig]', :immediately
    mode 0644
  end

  yum_package 'mesos' do
    version MesosHelper.mesos_rpm_version_release(node['mesos']['version'])
    not_if { ::File.exist? '/usr/local/sbin/mesos-master' }
  end
end

# Set init to 'stop' by default for mesos master.
# Running mesos::master recipe will reset this to 'start'
template '/etc/init/mesos-master.conf' do
  source 'mesos-init.erb'
  variables(
    type:   'master',
    action: 'stop'
  )
  not_if { node['recipes'].include?('mesos::master') }
end

# Set init to 'stop' by default for mesos slave.
# Running mesos::slave recipe will reset this to 'start'
template '/etc/init/mesos-slave.conf' do
  source 'mesos-init.erb'
  variables(
    type:   'slave',
    action: 'stop'
  )
  not_if { node['recipes'].include?('mesos::slave') }
end

if distro == 'debian'
  bash 'reload-configuration-debian' do
    user 'root'
    code <<-EOH
    update-rc.d -f mesos-master remove
    EOH
    not_if { ::File.exist? '/usr/local/sbin/mesos-master' }
  end
else
  bash 'reload-configuration' do
    user 'root'
    code <<-EOH
    initctl reload-configuration
    EOH
    not_if { ::File.exist? '/usr/local/sbin/mesos-master' }
  end
end
