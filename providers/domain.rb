#
# Author:: Derek Groh (<dgroh@arch.tamu.edu>)
# Cookbook Name:: windows_ad
# Provider:: domain
# 
# Copyright 2013, Texas A&M
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

require 'mixlib/shellout'

action :create do
  if exists?
    new_resource.updated_by_last_action(false)
  else
    cmd = create_command
    cmd << " -DomainName #{new_resource.name}"
    cmd << " -SafeModeAdministratorPassword (convertto-securestring '#{new_resource.safe_mode_pass}' -asplaintext -Force)"
    cmd << " -Force:$true"

    if new_resource.type != 'forest'
      if !new_resource.domain_user.nil? && !new_resource.domain_user.empty? &&
         !new_resource.domain_pass.nil? && !new_resource.domain_pass.empty?
        cmd = create_ps_credential(new_resource.domain_user, new_resource.domain_pass) + cmd + " -Credential $mycreds"
      end
    end

    new_resource.options.each do |option, value|
      if value.nil?
        cmd << " -#{option}"
      else
        cmd << " -#{option} '#{value}'"
      end
    end

    powershell_script "create_domain_#{new_resource.name}" do
      code cmd
    end

    new_resource.updated_by_last_action(true)
  end
end

action :delete do
  if exists?
    cmd = "Uninstall-ADDSDomainController"
    cmd << " -LocalAdministratorPassword (ConverTTo-SecureString '#{new_resource.local_pass}' -AsPlainText -Force)"
    cmd << " -Force:$true"
    cmd << " -ForceRemoval"
    if last_dc?
      cmd << " -DemoteOperationMasterRole"
    end

    new_resource.options.each do |option, value|
      if value.nil?
        cmd << " -#{option}"
      else
        cmd << " -#{option} '#{value}'"
      end
    end

    powershell_script "remove_domain_#{new_resource.name}" do
      code cmd
    end

    new_resource.updated_by_last_action(true)
  else
    new_resource.updated_by_last_action(false)
  end
end

action :join do
  if exists?
    Chef::Log.error("The domain does not exist or was not reachable, please check your network settings")
    new_resource.updated_by_last_action(false)
  else
    if computer_exists?
      Chef::Log.debug("The computer is already joined to the domain")
      new_resource.updated_by_last_action(false)
    else
      powershell_script "join_#{new_resource.name}" do
        if node[:os_version] >= "6.2"
          code <<-EOH
            #{create_ps_credential(new_resource.domain_user, new_resource.domain_pass)}
            Add-Computer -DomainName #{new_resource.name} -Credential $mycreds -Force:$true -Restart
          EOH
        else
          code <<-EOH
            #{create_ps_credential(new_resource.domain_user, new_resource.domain_pass)}
            Add-Computer -DomainName #{new_resource.name} -Credential $mycreds -Restart
          EOH
        end
      end

    new_resource.updated_by_last_action(false)
    end

    new_resource.updated_by_last_action(true)
  end
end

action :unjoin do
  if computer_exists?
    powershell_script "unjoin_#{new_resource.name}" do
      code <<-EOH
      #{create_ps_credential(new_resource.domain_user, new_resource.domain_pass)}
      Remove-Computer -UnjoinDomainCredential $mycreds -Force:$true -Restart
      EOH
    end

    new_resource.updated_by_last_action(true)
  else
    Chef::Log.debug("The computer is already a member of a workgroup")
    new_resource.updated_by_last_action(false)
  end
end

def exists?
  ldap_path = new_resource.name.split(".").map! { |k| "dc=#{k}" }.join(",")
  check = Mixlib::ShellOut.new("powershell.exe -command [adsi]::Exists('LDAP://#{ldap_path}')").run_command
  check.stdout.match("True")
end

def computer_exists?
  comp = Mixlib::ShellOut.new("powershell.exe -command \"get-wmiobject -class win32_computersystem -computername . | select domain\"").run_command
  comp.stdout.include?(new_resource.name) or comp.stdout.include?(new_resource.name.upcase)
end

def last_dc?
  dsquery = Mixlib::ShellOut.new("dsquery server -forest").run_command
  dsquery.stdout.split("\n").size == 1
end

def create_command
  case new_resource.type
  when "forest"
    "Install-ADDSForest"
  when "domain"
    "install-ADDSDomain"
  when "replica"
    "Install-ADDSDomainController"
  when "read-only"
    "Add-ADDSReadOnlyDomainControllerAccount"
  end
end

def create_ps_credential(user, pass)
  return <<-EOH
  $secpasswd = ConvertTo-SecureString '#{pass}' -AsPlainText -Force
  $mycreds = New-Object System.Management.Automation.PSCredential ('#{user}', $secpasswd)
  EOH
end
