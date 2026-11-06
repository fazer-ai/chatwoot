require 'spec_helper'
require 'digest'
require 'fileutils'
require 'open3'
require 'tmpdir'

# The image ships without enterprise/, and this helper is what brings it in at boot: from the
# official tag, checked against the hash pinned when the image was built. What can go wrong
# here goes wrong on a paying installation, so each failure has to stop the boot with a
# message, and each success has to leave exactly the pinned tree where Rails looks for it.
#
# Run against a temporary directory shaped like the app, with the tarball served from disk
# (curl reads file:// URLs), so no example needs the network.
# rubocop:disable RSpec/DescribeClass -- the subject is a shell script, not a constant
RSpec.describe 'docker/entrypoints/helpers/enterprise.sh', type: :script do
  let(:work_dir) { Dir.mktmpdir }
  let(:app_dir) { File.join(work_dir, 'app') }
  let(:cache_dir) { File.join(work_dir, 'cache') }
  let(:version) { '4.19.0' }
  let(:tree) { { 'app/models/enterprise/thing.rb' => "module Enterprise::Thing; end\n", 'config/premium.yml' => "a: 1\n" } }
  let(:tarball) { File.join(work_dir, 'source.tar.gz') }
  # the tree hash as the helper defines it, computed here independently of the helper
  let(:pinned) do
    lines = tree.keys.map { |path| "enterprise/#{path}" }.sort.map do |path|
      "#{Digest::SHA256.hexdigest(tree.fetch(path.delete_prefix('enterprise/')))}  #{path}\n"
    end
    Digest::SHA256.hexdigest(lines.join)
  end

  before do
    helper = File.join(app_dir, 'docker/entrypoints/helpers/enterprise.sh')
    FileUtils.mkdir_p(File.dirname(helper))
    FileUtils.cp(File.expand_path('../../docker/entrypoints/helpers/enterprise.sh', __dir__), helper)
    FileUtils.chmod(0o755, helper)
    File.write(File.join(app_dir, 'VERSION_CW'), "#{version}\n")
    write_lock(version, pinned)
    build_tarball(tree)
  end

  after { FileUtils.remove_entry(work_dir) }

  def write_lock(locked_version, sha)
    File.write(File.join(app_dir, '.enterprise_lock'), "version=#{locked_version}\nsha256=#{sha}\n")
  end

  # A tarball laid out like GitHub's: one top directory named after the repository and the
  # tag, with the whole repository under it.
  def build_tarball(files, top: "chatwoot-#{version}")
    src = File.join(work_dir, 'src')
    FileUtils.rm_rf(src)
    files.each do |path, content|
      file = File.join(src, top, 'enterprise', path)
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, content)
    end
    FileUtils.mkdir_p(File.join(src, top, 'app'))
    File.write(File.join(src, top, 'app/not_enterprise.rb'), "# outside enterprise/\n")
    _out, err, status = Open3.capture3('tar', '-czf', tarball, '-C', src, top)
    raise err unless status.success?
  end

  def ensure_enterprise(env = {})
    defaults = { 'CW_EDITION' => 'ee', 'DISABLE_ENTERPRISE' => nil, 'CW_ENTERPRISE_CACHE_DIR' => cache_dir,
                 'CW_ENTERPRISE_SOURCE_URL' => "file://#{tarball}", 'CW_ENTERPRISE_FETCH_RETRIES' => '0' }
    Open3.capture3(defaults.merge(env), File.join(app_dir, 'docker/entrypoints/helpers/enterprise.sh'), 'ensure')
  end

  def installed
    root = File.join(app_dir, 'enterprise')
    Dir.glob('**/*', base: root).select { |path| File.file?(File.join(root, path)) }.sort
  end

  def cache_entry
    File.join(cache_dir, "#{version}-#{pinned}", 'enterprise')
  end

  it 'does nothing unless the edition asks for enterprise' do
    _out, err, status = ensure_enterprise('CW_EDITION' => nil)

    expect(status).to be_success
    expect(err).to include("edition 'unset'")
    expect(File).not_to exist(File.join(app_dir, 'enterprise'))
  end

  it 'does nothing when DISABLE_ENTERPRISE is set, since Rails would not load it anyway' do
    _out, _err, status = ensure_enterprise('DISABLE_ENTERPRISE' => 'true')

    expect(status).to be_success
    expect(File).not_to exist(File.join(app_dir, 'enterprise'))
  end

  it 'downloads, verifies and installs only enterprise/, and keeps it in the cache' do
    FileUtils.mkdir_p(File.join(app_dir, 'tmp/cache/bootsnap'))

    _out, err, status = ensure_enterprise

    expect(status).to be_success
    expect(err).to include('downloaded, verified and installed')
    expect(installed).to eq(tree.keys.sort)
    expect(File).to exist(File.join(cache_entry, 'config/premium.yml'))
    expect(File).not_to exist(File.join(app_dir, 'app/not_enterprise.rb'))
    expect(File).not_to exist(File.join(app_dir, 'tmp/cache/bootsnap'))
  end

  it 'installs from an intact cache without reaching the source' do
    ensure_enterprise
    FileUtils.rm_rf(File.join(app_dir, 'enterprise'))

    _out, err, status = ensure_enterprise('CW_ENTERPRISE_SOURCE_URL' => 'http://127.0.0.1:9/unreachable.tar.gz')

    expect(status).to be_success
    expect(err).to include('using cached enterprise/')
    expect(installed).to eq(tree.keys.sort)
  end

  it 'leaves a tree that is already in place alone' do
    ensure_enterprise

    _out, err, status = ensure_enterprise('CW_ENTERPRISE_SOURCE_URL' => 'http://127.0.0.1:9/unreachable.tar.gz')

    expect(status).to be_success
    expect(err).to include('already in place')
  end

  it 'replaces a tree in place that does not match the pin' do
    ensure_enterprise
    File.write(File.join(app_dir, 'enterprise/app/models/enterprise/thing.rb'), "# edited\n")

    _out, _err, status = ensure_enterprise

    expect(status).to be_success
    expect(File.read(File.join(app_dir, 'enterprise/app/models/enterprise/thing.rb'))).to eq(tree.fetch('app/models/enterprise/thing.rb'))
  end

  it 'downloads again when the cached tree was tampered with' do
    ensure_enterprise
    FileUtils.rm_rf(File.join(app_dir, 'enterprise'))
    File.write(File.join(cache_entry, 'config/premium.yml'), "a: 2\n")

    _out, err, status = ensure_enterprise

    expect(status).to be_success
    expect(err).to include('does not match the pinned hash')
    expect(File.read(File.join(app_dir, 'enterprise/config/premium.yml'))).to eq("a: 1\n")
    expect(File.read(File.join(cache_entry, 'config/premium.yml'))).to eq("a: 1\n")
  end

  it 'ignores a cache that holds another version and downloads this one' do
    other = File.join(cache_dir, "4.18.0-#{'0' * 64}", 'enterprise')
    FileUtils.mkdir_p(other)
    File.write(File.join(other, 'old.rb'), "# 4.18.0\n")

    _out, err, status = ensure_enterprise

    expect(status).to be_success
    expect(err).to include('downloaded, verified and installed')
    expect(installed).to eq(tree.keys.sort)
  end

  it 'refuses a download whose tree does not match the pinned hash, and caches nothing' do
    build_tarball(tree.merge('app/models/enterprise/thing.rb' => "module Enterprise::Thing; def x; end; end\n"))

    _out, err, status = ensure_enterprise

    expect(status).not_to be_success
    expect(err).to include("the image pins #{pinned}. Not starting")
    expect(File).not_to exist(File.join(app_dir, 'enterprise'))
    expect(Dir.children(cache_dir)).to be_empty
  end

  it 'stops the boot when the source cannot be reached and nothing is cached' do
    _out, err, status = ensure_enterprise('CW_ENTERPRISE_SOURCE_URL' => 'http://127.0.0.1:9/unreachable.tar.gz')

    expect(status).not_to be_success
    expect(err).to include('could not download enterprise/ for v4.19.0')
    expect(err).to include('set CW_EDITION=ce')
    expect(File).not_to exist(File.join(app_dir, 'enterprise'))
    expect(Dir.children(cache_dir)).to be_empty
  end

  it 'stops the boot when the tarball is not for the version in VERSION_CW' do
    build_tarball(tree, top: 'chatwoot-4.18.0')

    _out, err, status = ensure_enterprise

    expect(status).not_to be_success
    expect(err).to include('could not download enterprise/ for v4.19.0')
  end

  it 'stops the boot when the lock pins another version than the image carries' do
    write_lock('4.18.0', pinned)

    _out, err, status = ensure_enterprise

    expect(status).not_to be_success
    expect(err).to include('pins v4.18.0, but this image is v4.19.0')
  end

  it 'stops the boot when the image has no lock at all' do
    FileUtils.rm_f(File.join(app_dir, '.enterprise_lock'))

    _out, err, status = ensure_enterprise

    expect(status).not_to be_success
    expect(err).to include('no hash to check enterprise/ against')
  end

  it 'refuses to hash a tree that holds a symlink, whose target the hash would not cover' do
    dir = File.join(work_dir, 'linked/enterprise')
    FileUtils.mkdir_p(dir)
    File.symlink('/etc/hosts', File.join(dir, 'hosts'))

    _out, _err, status = Open3.capture3(File.join(app_dir, 'docker/entrypoints/helpers/enterprise.sh'), 'tree-hash', dir)

    expect(status).not_to be_success
  end
end
# rubocop:enable RSpec/DescribeClass
