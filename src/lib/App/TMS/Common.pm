package App::TMS::Common;
use strict;
our $VERSION = 0;

use Exporter qw(import);
use Perl::Module;
use Data::OrderedHash;

our @EXPORT = qw(
  $TMS_DIR
  $TMS_SETTINGS
  $TMS_INSTANCE_DB
  $STATUS_OK
  $STATUS_CLIENT_DIR
  $STATUS_CLIENT_DIR_MISSING
  $STATUS_TARGET_MODIFIED
  $STATUS_TARGET_MISSING
  $STATUS_TEMPLATE_MODIFIED
  $STATUS_TEMPLATE_MISSING
  $TEXT_STATUS
  $TEXT_STATUS_ITEM
);
our @EXPORT_OK = @EXPORT;
our %EXPORT_TAGS = (all=>\@EXPORT_OK);

our $TMS_DIR                        = '.tms';
our $TMS_SETTINGS                   = '.tms/settings.hf';
our $TMS_INSTANCE_DB                = '.tms/instances.hf';

our $STATUS_OK                      = '';
our $STATUS_CLIENT_DIR              = '*';
our $STATUS_CLIENT_DIR_MISSING      = '*!';
our $STATUS_TARGET_MODIFIED         = 'M';
our $STATUS_TARGET_MISSING          = 'D';
our $STATUS_TEMPLATE_MODIFIED       = 'U';
our $STATUS_TEMPLATE_MISSING        = '!';

our $TEXT_STATUS = <<__end;
Local Root: [#client_root]
Repository Root: [#repo_root]
__end

our $TEXT_STATUS_ITEM = <<__end;
Target: [#target]
Template: [#template]
Status: [#status]
[#:for (dep,sum) in dep_checksums]
Dependency: [#dep]
[#:end for]
[#:for (u) in use]
Using: [#u]
[#:end for]
[#:for (k,v) in vars]
Variable: [#k] = '[#v]'
[#:end for]
__end

1;
