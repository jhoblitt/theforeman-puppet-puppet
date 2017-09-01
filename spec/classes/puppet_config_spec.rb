require 'spec_helper'

describe 'puppet::config' do
  on_os_under_test.each do |os, facts|
    context "on #{os}" do

      case facts[:osfamily]
      when 'FreeBSD'
        dir_owner = 'puppet'
        dir_group = 'puppet'
        codedir   = '/usr/local/etc/puppet'
        confdir   = '/usr/local/etc/puppet'
        logdir    = '/var/log/puppet'
        rundir    = '/var/run/puppet'
        ssldir    = '/var/puppet/ssl'
        vardir    = '/var/puppet'
        sharedir  = '/usr/local/share/puppet'
      when 'windows'
        dir_owner = nil
        dir_group = nil
        codedir   = 'C:/ProgramData/PuppetLabs/puppet/etc'
        confdir   = 'C:/ProgramData/PuppetLabs/puppet/etc'
        logdir    = 'C:/ProgramData/PuppetLabs/puppet/var/log'
        rundir    = 'C:/ProgramData/PuppetLabs/puppet/var/run'
        ssldir    = 'C:/ProgramData/PuppetLabs/puppet/etc/ssl'
        vardir    = 'C:/ProgramData/PuppetLabs/puppet/var'
        sharedir  = 'C:/ProgramData/PuppetLabs/puppet/share'
      else
        dir_owner = 'root'
        dir_group = nil
        codedir   = '/etc/puppetlabs/code'
        confdir   = '/etc/puppetlabs/puppet'
        logdir    = '/var/log/puppetlabs/puppet'
        rundir    = '/var/run/puppetlabs'
        ssldir    = '/etc/puppetlabs/puppet/ssl'
        vardir    = '/opt/puppetlabs/puppet/cache'
        sharedir  = '/opt/puppetlabs/puppet'
      end

      let :facts do
        facts.merge(domain: 'example.org')
      end

      describe 'with default parameters' do
        let :pre_condition do
          'include ::puppet'
        end

        it 'should contain confdir' do
          should contain_file(confdir)
            .with_owner(dir_owner)
            .with_group(dir_group)
        end

        it 'should contain auth.conf' do
          should_not contain_file("#{confdir}/auth.conf").with_content(%r{^path /certificate_revocation_list/ca\nmethod find$})
          should contain_file("#{confdir}/auth.conf").with_content(%r{/puppet/v3/})
        end

        it 'should_not contain default_manifest setting in puppet.conf' do
          should_not contain_puppet__config__main("default_manifest")
        end

        it 'should_not contain default manifest /etc/puppet/manifests/default_manifest.pp' do
          should_not contain_file('/etc/puppet/manifests/default_manifest.pp')
        end

        it 'should_not contain reports setting in puppet.conf' do
          should_not contain_puppet__config__main("reports")
        end

        it 'should contain puppet.conf [main]' do
          should contain_puppet__config__main("vardir").with({'value' => "#{vardir}"})
          should contain_puppet__config__main("logdir").with({'value' => "#{logdir}"})
          should contain_puppet__config__main("rundir").with({'value' => "#{rundir}"})
          should contain_puppet__config__main("ssldir").with({'value' => "#{ssldir}"})
          should contain_puppet__config__main("privatekeydir").with({'value' => '$ssldir/private_keys { group = service }'})
          should contain_puppet__config__main("hostprivkey").with({'value' => '$privatekeydir/$certname.pem { mode = 640 }'})
          should contain_puppet__config__main("show_diff").with({'value' => 'false'})
          should contain_puppet__config__main("server").with({'value' => "#{facts[:fqdn]}"})
        end
      end

      describe 'with allow_any_crl_auth' do
        let :pre_condition do
          'class {"::puppet": allow_any_crl_auth => true}'
        end

        it 'should contain auth.conf with auth any' do
          should contain_file("#{confdir}/auth.conf").with_content(%r{^path /puppet-ca/v1/certificate_revocation_list/ca\nauth any$})
        end
      end

      describe 'with auth_allowed' do
        let :pre_condition do
          'class {"::puppet": auth_allowed => [\'$1\', \'puppetproxy\']}'
        end

        it 'should contain auth.conf with allow' do
          should contain_file("#{confdir}/auth.conf").with_content(%r{^allow \$1, puppetproxy$})
        end
      end

      describe "when dns_alt_names => ['foo','bar']" do
        let :pre_condition do
          "class { 'puppet': dns_alt_names => ['foo','bar'] }"
        end

        it 'should contain puppet.conf [main] with dns_alt_names' do
          should contain_puppet__config__main("dns_alt_names").with({'value' => ['foo','bar']})
        end
      end

      describe "when syslogfacility => 'local6'" do
        let :pre_condition do
          "class { 'puppet': syslogfacility => 'local6' }"
        end

        it 'should contain puppet.conf [main] with syslogfacility' do
          should contain_puppet__config__main("syslogfacility").with({'value' => 'local6'})
        end
      end

      describe "when puppetmaster => 'mymaster.example.com'" do
        let :pre_condition do
          "class { 'puppet': puppetmaster => 'mymaster.example.com' }"
        end

        it "should contain puppet.conf [main] with server = 'mymaster.example.com'" do
          should contain_puppet__config__main('server').with({'value' => 'mymaster.example.com'})
        end
      end

      describe "when module_repository => 'https://myforgeapi.example.com'" do
        let :pre_condition do
          "class { 'puppet': module_repository => 'https://myforgeapi.example.com' }"
        end

        it 'should contain puppet.conf [main] with module_repository' do
          should contain_puppet__config__main("module_repository").with({'value' => 'https://myforgeapi.example.com'})
        end
      end

      describe "when use_srv_records => true, and domain fact" do
        context 'is defined' do
          let :pre_condition do
            "class { 'puppet': use_srv_records => true }"
          end

          it 'should contain puppet.conf [main] with SRV settings' do
            should contain_puppet__config__main("use_srv_records").with({'value' => "true"})
            should contain_puppet__config__main("srv_domain").with({'value' => "example.org"})
            should contain_puppet__config__main("pluginsource").with({'value' => "puppet:///plugins"})
            should contain_puppet__config__main("pluginfactsource").with({'value' => "puppet:///pluginfacts"})
          end

          it 'should not contain server setting' do
            should_not contain_puppet__config__main('server')
          end
        end

        context 'is unset' do
          let(:facts) { facts.merge({domain: nil}) }
          let :pre_condition do
            'class { ::puppet:
               use_srv_records => true
            }'
          end

          it 'should fail with a helpful message' do
            should raise_error(Puppet::Error, /\$::domain fact found to be undefined and \$srv_domain is undefined/)
          end
        end

        context 'is overriden via param' do
          let :pre_condition do
            'class { "::puppet":
               use_srv_records => true,
               srv_domain      => "special_domain.com"
            }'
          end

          it 'should configure srv domain' do
            should contain_puppet__config__main('use_srv_records').with_value(true)
            should contain_puppet__config__main('srv_domain').with_value('special_domain.com')
          end
        end
      end

      describe 'when listen and listen_to has values' do
        let :pre_condition do
          'class {"::puppet": listen => true, listen_to => ["node1.example.com","node2.example.com",],}'
        end

        it 'should contain auth.conf with auth any' do
          should contain_file("#{confdir}/auth.conf").with_content(%r{^path /run\nauth any\nmethod save\nallow node1.example.com,node2.example.com$})
        end
      end

      describe 'when listen and puppetmaster has value' do
        let :pre_condition do
          'class {"::puppet": listen => true, puppetmaster => "master.example.com",}'
        end

        it 'should contain auth.conf with auth any' do
          should contain_file("#{confdir}/auth.conf").with_content(%r{^path /run\nauth any\nmethod save\nallow master.example.com$})
        end
      end

      describe 'when listen => true and default value is used' do
        let :pre_condition do
          'class {"::puppet": listen => true}'
        end

        it 'should contain auth.conf with auth any' do
          should contain_file("#{confdir}/auth.conf").with_content(%r{^path /run\nauth any\nmethod save\nallow #{facts[:fqdn]}$})
        end
      end

      describe 'with additional settings' do
        let :pre_condition do
          "class {'puppet':
              additional_settings => {disable_warnings => deprecations},
           }"
        end

        it 'should configure puppet.conf' do
          should contain_puppet__config__main("disable_warnings").with({'value' => "deprecations"})
        end
      end

      describe 'puppetmaster parameter overrides global puppetmaster' do
        let(:pre_condition) { "class {'puppet': puppetmaster => 'mymaster.example.com'}" }
        let :facts do
          facts.merge({:puppetmaster => 'global.example.com'})
        end
        it do
          should contain_puppet__config__main('server').with({'value'  => 'mymaster.example.com'})
        end
      end

      describe 'global puppetmaster overrides fqdn' do
        let(:pre_condition) { "include ::puppet" }
        let :facts do
          facts.merge({:puppetmaster => 'mymaster.example.com'})
        end
        it do
          should contain_puppet__config__main('server').with({'value'  => 'mymaster.example.com'})
        end
      end
    end
  end
end
