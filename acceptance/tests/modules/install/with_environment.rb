test_name 'puppet module install (with environment)'
require 'puppet/acceptance/module_utils'
extend Puppet::Acceptance::ModuleUtils

hosts.each do |host|
  skip_test "skip tests requiring forge certs on solaris and aix" if host['platform'] =~ /solaris/
end

tmpdir = master.tmpdir('environmentpath')

module_author = "pmtacceptance"
module_name   = "nginx"

orig_installed_modules = get_installed_modules_for_hosts hosts
teardown do
  rm_installed_modules_from_hosts orig_installed_modules, (get_installed_modules_for_hosts hosts)
end

step 'Setup'

stub_forge_on(master)

puppet_conf = generate_base_legacy_and_directory_environments(tmpdir)

check_module_install_in = lambda do |environment_path, module_install_args|
  on master, "puppet module install #{module_author}-#{module_name} --config=#{puppet_conf} #{module_install_args}" do
    assert_module_installed_ui(stdout, module_author, module_name)
    assert_match(/#{environment_path}/, stdout,
          "Notice of non default install path was not displayed")
  end
  assert_module_installed_on_disk(master, module_name, environment_path)
end

step 'Install a module into a non default legacy environment' do
  check_module_install_in.call("#{tmpdir}/legacyenv/modules",
                               "--environment=legacyenv")
end

step 'Enable directory environments' do
  on master, puppet("config", "set",
                    "environmentpath", "#{tmpdir}/environments",
                    "--section", "main",
                    "--config", puppet_conf)
end

step 'Install a module into a non default directory environment' do
  check_module_install_in.call("#{tmpdir}/environments/direnv/modules",
                              "--environment=direnv")
end

step 'Prepare a separate modulepath'
modulepath_dir = master.tmpdir("modulepath")
apply_manifest_on(master, <<-MANIFEST , :catch_failures => true)
  file {
    [
      '#{tmpdir}/environments/production',
      '#{modulepath_dir}',
    ]:

    ensure => directory,
    owner => #{master['user']},
  }
MANIFEST

step "Install a module into --modulepath #{modulepath_dir} despite the implicit production directory env existing" do
  check_module_install_in.call(modulepath_dir, "--modulepath=#{modulepath_dir}")
end

step "Uninstall so we can try a different scenario" do
  on master, "puppet module uninstall #{module_author}-#{module_name} --config=#{puppet_conf} --modulepath=#{modulepath_dir}"
end

step "Install a module into --modulepath #{modulepath_dir} with a directory env specified" do
  check_module_install_in.call(modulepath_dir,
                               "--modulepath=#{modulepath_dir} --environment=direnv")
end
