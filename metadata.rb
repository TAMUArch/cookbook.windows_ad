name             'windows_ad'
maintainer       'Texas A&M'
maintainer_email 'dgroh@arch.tamu.edu'
license          'MIT'
description      'Installs/Configures windows active directory'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.5.0'
supports         'windows', '>= 6.1'

depends          'windows'
depends          'compat_resource', '~> 12.7.1'

