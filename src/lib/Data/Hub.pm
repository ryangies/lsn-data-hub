package Data::Hub;
use strict;
use 5.008003;
our $VERSION = 0.1;

use Exporter;
use Perl::Module;
use Error::Simple;
use Scalar::Util qw(weaken);
use Data::Hub::Util qw(:all);
use Data::Hub::Container;
use Data::OrderedHash;
use Data::Hub::FileSystem::Node;
use Data::Hub::FileSystem::AccessLog;
use Data::CompositeHash;
use Tie::Hash;
use Cwd qw(cwd);

# Package vars

push our @ISA, qw(Tie::ExtraHash Data::Hub::Container);
our @EXPORT = ();
our @EXPORT_OK = qw($Hub);
our %EXPORT_TAGS = (all => [@EXPORT_OK],);
our %Cache = ();
our $Hub = undef;

# ------------------------------------------------------------------------------
# import - Instantiate C<$Hub> when requested
# import $package, @symbols
# ------------------------------------------------------------------------------

sub import {
  my $caller = scalar(caller) || '';
  my $arg1 = $_[1] || '';
  if ($arg1 eq '$Hub' && $caller eq 'main') {
    if (defined $Hub) {
      die sprintf("Unexpected initialization! %s::\$Hub", __PACKAGE__);
    } else {
      $Hub = __PACKAGE__->new();
      $Hub->parse_env;
    }
  }
  goto &Exporter::import;
}

# OO interface

sub new {
  my $class = ref($_[0]) || $_[0];
  my $path = path_normalize($_[1] || cwd());
  throw Error::Simple "$!: $path" unless -d $path;
  throw Error::Simple "Path is not absolute: $path"
    unless path_is_absolute($path);
  my $self =  bless {}, $class;
  tie %$self, $class, $path;
  $self->mount_sys;
  $self->expire;
  $self;
}

sub expire {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self);

  # Our cache is valid only during the snapshot (i.e., request) where the
  # weakened references become undefined when the target is deleted.  When
  # a new snapshot is taken, the cache cannot be used as it would need to
  # scan for the existence of each item anyway--which is what 'get' does
  # before it caches the value.
  %{$tied->__cache} = ();

  # The file-system access logically belongs to this snapshot as it
  # reflects the nodes which have been accessed.
  $tied->__fs_access->clear();
  $tied->__fs_change->clear();

  # This is the godly request number/count which is used by all filesystem
  # nodes which are instantiated under this Hub's get/set mechanism.  When
  # this number is incremented the nodes will then actually stat their
  # storage in order to check their freshness.
  ${$tied->__req_count}++;

}

sub mount_sys {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->mount('/sys', {});
}

sub parse_env {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my @argv = @ARGV;
  my $opts = {};
  my $env = new Data::OrderedHash();
  %$env = map {($_, $ENV{$_})} sort keys %ENV;
  my_opts(\@argv, $opts);
  $$self{'/sys/ENV'} = $env;
  $$self{'/sys/OPTS'} = $opts;
  $$self{'/sys/ARGV'} = [@argv];
  $self;
}

sub mount_base {
  my $self = shift;
  my $path = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self);
  $tied->__all->push(Data::Hub::FileSystem::Node->new($path, $tied));
}

sub mount {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self);
  while (@_) {
    my $k = shift;
    my $v = shift;
    $k =~ s/^\///;
    throw Error::Simple "Mount point must specify a root node"
      if index($k, '/') >= $[;
    if (ref($v)) {
      # $v is an object (could be a fs node)
      $tied->__mounts->{$k} = $v;
      $tied->__persistent->{$k} = $v->get_path if can($v, 'get_path');
    } else {
      # $v must be an absolute path (TODO enforce).
      # set __persistent before call to new so that addr_to_path works when
      # called by the Node constructor.
      $tied->__persistent->{$k} = $v;
      my $node = Data::Hub::FileSystem::Node->new($v, $tied);
      $tied->__mounts->{$k} = $node;
    }
  }
}

sub umount {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  for (@_) {
    s/^\///;
    throw Error::Simple "Mount point must specify a root node"
      if index($_, '/') >= $[;
    delete tied(%$self)->__mounts->{$_};
    tied(%$self)->__remove_cache($_);
    delete tied(%$self)->__persistent->{$_};
  }
}

# OO Utility methods

sub is_mount {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $addr = shift;
  $addr =~ s/^\///;
  return tied(%$self)->__persistent->{$addr} ? 1 : 0;
}

sub add_handler {
  my $self = shift if isa($_[0], __PACKAGE__);
  Data::Hub::FileSystem::Node::Add_Handler(@_);
}

sub add_handler2 {
  my $self = shift if isa($_[0], __PACKAGE__);
  Data::Hub::FileSystem::Node::Add_Handler2(@_);
}

sub fs_access_log {
  my $self = shift;
  tied(%$self)->__fs_access;
}

sub fs_change_log {
  my $self = shift;
  tied(%$self)->__fs_change;
}

# ------------------------------------------------------------------------------
# uri - Return a URI to the specified resource
#
# uri $address
# uri $address, -proto => 'https'
#
# Where:
#
#   $address may be an absolute address under the Hub root
#
#     '/path/to/resource'
#
#   or a relative path:
#
#     './resource'
#     '../path/to/resource'
#
# A web server MUST populate C</sys/server/uri> with the server origin. For
# example:
#
#   //example.com
#   //example.com:90
# 
# and MAY populate C</sys/request/scheme> with either:
#
#   http
#   https
#
# The C<-proto> option takes precedence to C</sys/request/scheme> and the
# default scheme of C<http>.
#
# If C</sys/server/uri> is not populated, then the full C<file://> URI is
# produced.
# ------------------------------------------------------------------------------

sub uri {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $result = '';
  my $addr = tied(%$self)->__resolve_addr(shift) or return;
  my $opts = my_opts(\@_);
  my $server_uri = $self->get('/sys/server/uri');
  if ($server_uri) {
    my $proto = $$opts{'proto'} || $self->get('/sys/request/scheme') || 'http';
    $result = sprintf '%s:%s%s', $proto, $server_uri, $addr;
  } else {
    my $path = $self->addr_to_path($addr);
    $result = sprintf 'file://%s', $path;
  }
  $result;
}

sub path_to_addr {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  tied(%$self)->__path_to_addr(@_);
}

sub path_relative {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $path = tied(%$self)->__path_to_addr(@_) or return;
  substr $path, 1; # trim leading '/'
}

sub path_absolute {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->addr_to_path(@_);
}

sub addr_to_path {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $addr = $_[0] or return;
  my $root_key = addr_shift($addr) || '/';
  my $root_node = $self->{$root_key};
  unless ($root_node) {
    $root_node = $self->{'/'};
    $addr = $_[0];
  }
  return unless can($root_node, 'get_path');
  my $path = $root_node->get_path;
  $path .= '/' . $addr if $addr;
  return path_normalize($path);
}

sub addr_to_storage {
  my $self = shift;
  my $addr = shift or return;
  my $node = tied(%$self)->FETCH($addr);
  while ($addr && defined $node && !isa($node, FS('Node'))) {
    addr_pop $addr;
    $node = tied(%$self)->FETCH($addr);
  }
  $addr ? $node : undef;
}

sub find_storage {
  my $self = shift;
  my $addr = shift or return;
  my $node = tied(%$self)->FETCH($addr);
  while (!isa($node, FS('Node'))) {
    addr_pop $addr;
    last unless $addr;
    $node = tied(%$self)->FETCH($addr);
  }
  $addr ? $node : undef;
}

sub get_fs_root {
  my $self = shift;
  tied(%$self)->__fs_root;
}

# sub get_fs_node {
#   my $self = shift or die;
#   my $addr = shift or return;
#   my $root = tied(%$self)->__fs_root or return;
#   $root->get_concrete($addr);
# }

# Data::Hub::Courier interface

sub get {
  my $self = shift;
  tied(%$self)->FETCH(@_);
}

sub set {
  my $self = shift;
  tied(%$self)->STORE(@_);
}

sub list {
  my $self = shift;
  my $value = tied(%$self)->FETCH(@_);
  $value = Data::Hub::Container->new([]) unless defined $value;
  return $value if (isa($value, 'ARRAY'));
  return $value if (isa($value, 'Data::Hub::Subset'));
  Data::Hub::Container->new([$value]);
}

sub vivify {
  my $self = shift;
  my $addr = shift;
  my $type = shift || FS('Directory');
  my $tied = tied(%$self);
#warn "viv-get: $addr\n";
  my $node = $tied->FETCH($addr);
  return $node if defined ($node);
  $node = $type->new('???', $tied);
#warn "viv-set2: $node\n";
  $tied->STORE($addr, $node);
#warn "viv-set3: $addr\n";
#  Removed b/c $addr does not retain relative paths
#  $tied->__all->{$addr};
}

sub free {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self);
  $self->expire;
  my $dir = $tied->__all->{'/'} or return;
  $dir->free;
}

# Tie interface

sub __all         { exists $_[1] ? $_[0][0] = $_[1] : $_[0][0]; }
sub __mounts      { exists $_[1] ? $_[0][1] = $_[1] : $_[0][1]; }
sub __cache       { exists $_[1] ? $_[0][2] = $_[1] : $_[0][2]; }
sub __fs_access   { exists $_[1] ? $_[0][3] = $_[1] : $_[0][3]; }
sub __req_count   { exists $_[1] ? $_[0][4] = $_[1] : $_[0][4]; }
sub __persistent  { exists $_[1] ? $_[0][5] = $_[1] : $_[0][5]; }
sub __dir_stack   { exists $_[1] ? $_[0][6] = $_[1] : $_[0][6]; }
sub __fs_root     { exists $_[1] ? $_[0][7] = $_[1] : $_[0][7]; }
sub __fs_change   { exists $_[1] ? $_[0][8] = $_[1] : $_[0][8]; }

sub TIEHASH {
  my $fs_access = Data::Hub::FileSystem::AccessLog->new();
  my $fs_change = Data::Hub::FileSystem::AccessLog->new();
  my $req_count = 0;
  my $mounts = {};
  my $cache = {};
  my $persistent = {'/' => $_[1]};
  my $dir_stack = ['/'];
  my $tied = bless [
    undef, # __all
    $mounts, # __mounts
    $cache, # __cache
    $fs_access, # __fs_access
    \$req_count, # __req_count
    $persistent, # __persistent
    $dir_stack, # __dir_stack
    undef, # __fs_root
    $fs_change, # __fs_change
  ], $_[0];
  my $home = Data::Hub::FileSystem::Node->new($_[1], $tied);
  my $all = Data::CompositeHash->new($home);
  $all->unshift($mounts);
  $tied->__all($all);
  $tied->__fs_root($home);
  $tied;
}

sub STORE {
  my $tied = shift;
  my $addr = shift;
  my $value = shift;
  my $p_addr = $addr;
  my $last_key = addr_pop($p_addr);
  my $p_value = $p_addr ? $tied->FETCH($p_addr) : undef;
  if (defined $p_value) {
    return Data::Hub::Courier::_set_value($p_value, $last_key, $value);
  } else {
    if ($addr =~ s!^\./!$tied->__dir_stack->[0].'/'!e) {
      $addr = addr_normalize($addr);
    }
    return $tied->__all->{$addr} = $value;
  }
}

sub FETCH {
  my $tied = shift;
  my $addr = $tied->__resolve_addr(shift);
  my $value = $tied->__cache->{$addr};
  return $value if defined $value;
  my $p_addr = $addr;
  my $name = addr_pop($p_addr);
  if ($p_addr && $p_addr ne '/') {
    my $p_value = $tied->__cache->{$p_addr};
    $p_value = $tied->__fetch($p_addr) unless defined $p_value;
    return unless defined $p_value && ref($p_value);
    $value = is_abstract_key($name)
      ? $p_value->get($name)
      : curry($p_value->_get($name)); # _get needed (vs _get_value for Subsets)
  } else {
    $value = $tied->__fetch($addr);
  }
  $value;
}

sub __resolve_addr {
  my $tied = shift;
  my $addr = shift;
  if ($addr =~ /^\./) {
    my $cwd = $tied->__dir_stack->[0];
    $addr = addr_normalize("$cwd/$addr");
  }
  $addr;
}

sub __fetch {
  my $value = $_[0]->__all->{$_[1]};
  return $value unless ref $value && ! isa($value, 'Data::Hub::Subset');
  $_[0]->__cache->{$_[1]} = $value;
  weaken $_[0]->__cache->{$_[1]};
  $value;
}

sub DELETE {
  my $tied = shift;
  return unless defined $_[0];
  delete $tied->__all->{$_[0]};
  $tied->__remove_cache($_[0]);
}

sub __path_to_addr {
  my $tied = shift;
  my $path = addr_normalize($_[0]);
  my $addr = undef;
#warn "path-to-addr: $path\n";
  if (path_is_absolute($path)) {
    my $persistent = $tied->__persistent;
    foreach my $root_addr (keys %$persistent) {
      my $root_path = $persistent->{$root_addr};
#warn "  $root_path\n";
      if ($path eq $root_path) {
        return index($root_addr, '/') == 0 ? $root_addr : "/$root_addr";
      }
      if (index($path, $root_path) == 0) {
        my $subpath = substr $path, length($root_path);
        $addr = path_normalize("/$root_addr/$subpath");
        last;
      }
    }
  } else {
    $addr = '/' . $path;
  }
  defined($addr) && $addr ne $_[0] ? $addr : undef;
}

sub __remove_cache {
  my $tied = shift;
  my $addr = shift or throw Error::IllegalArg;
  for (keys %{$tied->__cache}) {
    /^$addr/ and delete $tied->__cache->{$_};
  }
}

1;

__END__

sub pwa_push {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $dir = shift or throw Error::MissingArg;
  unshift @{tied(%$self)->__dir_stack}, $dir;
}

sub pwa_pop {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  shift @{tied(%$self)->__dir_stack};
}

sub pwa {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  tied(%$self)->__dir_stack->[0];
}
