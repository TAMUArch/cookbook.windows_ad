#
# Author:: Derek Groh (<dgroh@arch.tamu.edu>)
# Cookbook:: windows_ad
# Resource:: domain
#
# Copyright:: 2013, Texas A&M

resource_name :windows_ad_domain
provides :windows_ad_domain

default_action :create

property :domain_user, String, required: true
property :domain_pass, String, required: true
property :parent_domain_name, String
property :restart, [TrueClass, FalseClass], required: true
property :type, String, default: 'forest'
property :safe_mode_pass, String, required: true
property :options, Hash, default: {}
property :local_pass, String
property :replica_type, String, default: 'domain'

require 'mixlib/shellout'

ENUM_NAMES = %w[(Win2003) (Win2008) (Win2008R2) (Win2012) (Win2012R2) (Default)].freeze

action :create do
  if exists?
  else
    if Chef::Version.new(node['os_version']) >= Chef::Version.new('6.2')
      cmd = create_command
      cmd << " -DomainName #{new_resource.name}"
      cmd << " -SafeModeAdministratorPassword (convertto-securestring '#{new_resource.safe_mode_pass}' -asplaintext -Force)"
      cmd << ' -Force:$true'
      cmd << ' -NoRebootOnCompletion' unless new_resource.restart
    elsif
      cmd = 'dcpromo -unattend'
      cmd << " -newDomain:#{new_resource.type}"
      cmd << " -NewDomainDNSName:#{new_resource.name}"
      cmd << if !new_resource.restart
               ' -RebootOnCompletion:No'
             else
               ' -RebootOnCompletion:Yes'
             end
      cmd << " -SafeModeAdminPassword:(convertto-securestring '#{new_resource.safe_mode_pass}' -asplaintext -Force)"
      cmd << " -ReplicaOrNewDomain:#{new_resource.replica_type}"
    end
    Chef::Log.debug("cmd is #{cmd}")
    cmd << format_options(new_resource.options)

    powershell_script "create_domain_#{new_resource.name}" do
      code cmd
      returns [0, 1, 2, 3, 4]
    end
  end
end

action :delete do
  if Chef::Version.new(['os_version']) <= Chef::Version.new('6.1')
    Chef::Log.warn('This version of Windows Server is currently unsupported
                    beyond installing the required roles and features. Help us
                    out by submitting a pull request.')
  end
  if exists?
    cmd = 'Uninstall-ADDSDomainController'
    cmd << " -LocalAdministratorPassword (ConverTTo-SecureString '#{new_resource.local_pass}' -AsPlainText -Force)"
    cmd << ' -Force:$true'
    cmd << ' -ForceRemoval'
    cmd << ' -DemoteOperationMasterRole' if last_dc?
    cmd << format_options(new_resource.options)

    powershell_script "remove_domain_#{new_resource.name}" do
      code cmd
    end
  end
end

action_class do
  def exists?
    ldap_path = new_resource.name.split('.').map! { |k| "dc=#{k}" }.join(',')
    check = Mixlib::ShellOut.new("powershell.exe -command [adsi]::Exists('LDAP://#{ldap_path}')").run_command
    check.stdout.match('True')
  end

  def computer_exists?
    comp = Mixlib::ShellOut.new('powershell.exe -command "get-wmiobject -class win32_computersystem -computername . | select domain"').run_command
    stdout = comp.stdout.downcase
    stdout.include?(new_resource.name.downcase)
  end

  def last_dc?
    dsquery = Mixlib::ShellOut.new('dsquery server -forest').run_command
    dsquery.stdout.split("\n").size == 1
  end

  def create_command
    if Chef::Version.new(node['os_version']) > Chef::Version.new('6.2')
      cmd = ''
      if new_resource.type != 'forest'
        cmd << "$secpasswd = ConvertTo-SecureString '#{new_resource.domain_pass}' -AsPlainText -Force;"
        cmd << "$mycreds = New-Object System.Management.Automation.PSCredential  ('#{new_resource.domain_user}', $secpasswd);"
      end
      case new_resource.type
      when 'forest'
        cmd << 'Install-ADDSForest'
      when 'domain'
        cmd << 'Install-ADDSDomain -Credential $mycreds'
        if parent_domain_name && !parent_domain_name.empty?
          cmd << ' -DomainType ChildDomain'
          cmd << " -ParentDomainName '#{new_resource.parent_domain_name}'"
        end
      when 'replica'
        cmd << 'Install-ADDSDomainController -Credential $mycreds'
      when 'read-only'
        cmd << 'Add-ADDSReadOnlyDomainControllerAccount -Credential $mycreds'
      end
    else
      case new_resource.type
      when 'forest'
        'forest'
      when 'domain'
        'domain'
      when 'read-only'
        'domain'
      when 'replica'
        'replica'
      end
    end
  end

  def format_options(options)
    options.reduce('') do |cmd, (option, value)|
      cmd << if value.nil?
               " -#{option}"
             elsif ENUM_NAMES.include?(value) || value.is_a?(Numeric)
               if Chef::Version.new(node['os_version']) >= Chef::Version.new('6.2')
                 " -#{option} #{value}"
               else
                 " -#{option}:#{value}"
               end
             else
               if Chef::Version.new(node['os_version']) >= Chef::Version.new('6.2')
                 " -#{option} '#{value}'"
               else
                 " -#{option}:'#{value}'"
               end
             end
    end
  end
end
