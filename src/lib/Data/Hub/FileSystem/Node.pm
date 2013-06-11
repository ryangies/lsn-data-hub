package Data::Hub::FileSystem::Node;
use strict;
use Tie::Hash;
use Perl::Module;
use Error::Programatic;
use Error::Logical;
use Data::OrderedHash;
use Data::Hub::Util qw(:all);
use Data::Hub::Container;
use Data::Hub::FileSystem::AccessLog;
use Fcntl qw(S_ISREG S_ISDIR S_ISBLK S_ISCHR S_IFMT);
push our @ISA, qw(Tie::ExtraHash Data::Hub::Container);

our $VERSION = 0.1;

# Implementing classes (FileSystem handlers)
our @Handlers = ();

# ------------------------------------------------------------------------------
# Add_Handler - Add a filesystem node handler
# Add_Handler 'Package::Name', %criteria
#
# criteria:
#
#   -type=d         # Directory
#   -type=f         # Regular file
#   -type=T         # Text file
#   -type=B         # Binary file
#   -type=!         # Does not exist
#   -path=$regex    # Path (with filename) matches $regex
#   -crown=$regex   # File's crown matches $regex
#
# ------------------------------------------------------------------------------

sub Add_Handler {
  my ($opts, $pkg) = my_opts(\@_);
  my ($fn) = $pkg =~ /^([\d\w:]+)/;
  $fn =~ s/::/\//g;
  $fn .= '.pm';
  require $fn;
  unshift @Handlers, {pkg=>$pkg, %$opts};
}

# Don't try to require the module
sub Add_Handler2 {
  my ($opts, $pkg) = my_opts(\@_);
  unshift @Handlers, {pkg=>$pkg, %$opts};
}

sub Get_Pkg {
  my $path = shift;
  my $default = shift || __PACKAGE__;
  my $stat = shift || str_ref();
  tie my $crown, 'Data::Hub::FileSystem::Node::Crown', $path;
  $$stat ||= stat $path;
  my $handler = grep_first {_Match($_, $path, \$crown)} @Handlers;
  return defined $handler ? $handler->{pkg} : $default;
}

sub _Match {
  my ($h, $path, $crown) = @_;
  if (defined $$h{'type'}) {
    return 0 if ($$h{'type'} eq 'd' && ! -d _);
    return 0 if ($$h{'type'} eq 'T' && ! -T _);
    return 0 if ($$h{'type'} eq 'B' && ! (-B _ && ! -d _));
    return 0 if ($$h{'type'} eq 'f' && ! -f _);
    return 0 if ($$h{'type'} eq '!' && -e _);
  }
  if (defined $$h{'path'}) {
    return 0 if ($path !~ /$$h{'path'}/i);
  }
  if (defined $$h{'crown'}) {
    return 0 if ($$crown !~ /$$h{'crown'}/);
  }
  1;
}

# ------------------------------------------------------------------------------
# Handlers added first are matched last.
# ------------------------------------------------------------------------------

# Core handlers
Add_Handler(q/Data::Hub::FileSystem::File/,        '-type=f');
Add_Handler(q/Data::Hub::FileSystem::BinaryFile/,  '-type=B');
Add_Handler(q/Data::Hub::FileSystem::Directory/,   '-type=d');
Add_Handler(q/Data::Hub::FileSystem::TextFile/,    '-type=T');
Add_Handler(q/Data::Hub::FileSystem::TextFile/,    '-type=!', '-path=\.txt$');

# PerlModule
Add_Handler(q/Data::Hub::FileSystem::PerlModule/,  '-type=T', '-crown=^#\s*PerlModule\b');

# HashFile
Add_Handler(q/Data::Hub::FileSystem::HashFile/,    '-type=!', '-path=\.hf$');
Add_Handler(q/Data::Hub::FileSystem::HashFile/,    '-type=T', '-path=\.hf$');
Add_Handler(q/Data::Hub::FileSystem::HashFile/,    '-type=T', '-crown=^#\s*HashFile\b');

# JSONFile
Add_Handler(q/Data::Hub::FileSystem::JSONFile/,    '-type=!', '-path=\.json$');
Add_Handler(q/Data::Hub::FileSystem::JSONFile/,    '-type=T', '-path=\.json$');

# YAMLFile
Add_Handler(q/Data::Hub::FileSystem::YAMLFile/,    '-type=!', '-path=\.ya?ml$');
Add_Handler(q/Data::Hub::FileSystem::YAMLFile/,    '-type=T', '-path=\.ya?ml$');

# Images
Add_Handler(q/Data::Hub::FileSystem::ImageFile/,    '-type=B', '-path=\.(jpe?g|gif|png)');

# Fixes (binary files which aren't always picked up by -B)
Add_Handler(q/Data::Hub::FileSystem::BinaryFile/,  '-path=\.(pdf|run)$');

# ------------------------------------------------------------------------------
# new - Consructor
# new $path
# new $path, \%Data::Hub
# ------------------------------------------------------------------------------

sub new {
  my $pkg = ref($_[0]) ? ref(shift) : shift;
  my $path = shift;
  my $stat = undef;

  if ($pkg eq __PACKAGE__) {
    $pkg = Get_Pkg($path, undef, \$stat);
  } else {
    $stat = stat $path;
  }

  my $self = bless {}, $pkg;
  tie %$self, $pkg, $path, $stat, @_;

  return $self;
}

# ------------------------------------------------------------------------------
# get_path - Return the full physical path to this node.
# get_path
# Base method.
# ------------------------------------------------------------------------------

sub get_path {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  tied(%$self)->__path;
}

# ------------------------------------------------------------------------------
# get_addr - Return the full physical path to this node.
# get_addr
# Base method.
# ------------------------------------------------------------------------------

sub get_addr {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  tied(%$self)->__addr;
}

# ------------------------------------------------------------------------------
# get_name - Return the file name of this node.
# get_name
# Base method.
# ------------------------------------------------------------------------------

sub get_name {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  addr_name(tied(%$self)->__addr);
}

# ------------------------------------------------------------------------------
# get_type - Return the Hub type signature for this node
# get_type
# Base method.
# ------------------------------------------------------------------------------

sub get_type {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  tied(%$self)->__scan();
  return typeof(tied(%$self)->__path, $self);
}

# ------------------------------------------------------------------------------
# set_data - Set the data segment of this node
# ------------------------------------------------------------------------------

sub set_data {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $value = shift;
  throw Error::Programatic 'provide a hash' unless isa($value, 'HASH');
  tied(%$self)->__scan();
  my $data = tied(%$self)->__data;
  %$data = %$value;
}

# ------------------------------------------------------------------------------
# get_data - Return the data segment of this node
# ------------------------------------------------------------------------------

sub get_data {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  tied(%$self)->__scan();
  tied(%$self)->__data();
}

# ------------------------------------------------------------------------------
# set_content - Set the content segment of this node
# ------------------------------------------------------------------------------

sub set_content {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  tied(%$self)->__scan();
  tied(%$self)->__content(@_);
}

# ------------------------------------------------------------------------------
# get_content - Return the content segment of this node
# ------------------------------------------------------------------------------

sub get_content {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  tied(%$self)->__scan();
  tied(%$self)->__content();
}

# ------------------------------------------------------------------------------
# set_raw_content - Set the literal contents
# ------------------------------------------------------------------------------

sub set_raw_content {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  tied(%$self)->__scan();
  tied(%$self)->__raw_content(@_);
}

# ------------------------------------------------------------------------------
# get_raw_content - Return the literal contents
# ------------------------------------------------------------------------------

sub get_raw_content {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  tied(%$self)->__scan();
  tied(%$self)->__raw_content();
}

# ------------------------------------------------------------------------------
# get_stat - Get the stat record for this node
# get_stat
# ------------------------------------------------------------------------------

sub get_stat {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self);
  defined($tied->__checkpoint) && $tied->__checkpoint == ${$tied->__global_cp}
    ? $tied->__stat : stat $tied->__path;
}

# ------------------------------------------------------------------------------
# get_mtime - Modified time of persistent storage
# get_mtime
# ------------------------------------------------------------------------------

sub get_mtime {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  tied(%$self)->__scan;
  tied(%$self)->__disk_mtime;
}

sub rename {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $new_name = shift;
  throw Error::IllegalArg unless defined($new_name);
  my $tied = tied(%$self);
  my $path = $tied->__path;
  my $cwd = path_parent($path);
  my $new_path = addr_join($cwd, $new_name);
  throw Error::Logical 'Path mismatch' unless $cwd eq path_parent($new_path);
  rename $path, $new_path;
  $tied->__path($new_path);
  my $stat = stat $tied->__path or die "No stat after rename";
  $tied->__stat($stat);
  $tied->__mtime(int(time));
  $tied->__disk_mtime($stat ? $stat->mtime : undef);
  $self;
}

# ------------------------------------------------------------------------------
# save - Save changes made to this node
# ------------------------------------------------------------------------------

sub save {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self);
  $tied->__scan();
  return if (-e $tied->__path && !$tied->__mtime); # Have not read
#$tied->__errlog( " <write> " . $tied->__path . "\n");
  $tied->__write_to_disk();
  my $stat = stat $tied->__path or die "No stat after save";
  $tied->__stat($stat);
  $tied->__mtime(int(time));
  $tied->__disk_mtime($stat ? $stat->mtime : undef);
  $tied->__track_change();
  unless(isa($self, Get_Pkg($tied->__path, undef, \$stat))) {
    # We are no longer a valid package for this path
    $tied->__checkpoint(0);
  }
  $self;
}

# ------------------------------------------------------------------------------
# expire - Detect changes made in persistent storage on next access
# expire
# ------------------------------------------------------------------------------

sub expire {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self);
  $tied->__checkpoint(0);
}

# ------------------------------------------------------------------------------
# refresh - Detect changes made in persistent storage
# refresh
# refresh $key
# ------------------------------------------------------------------------------

sub refresh {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  tied(%$self)->__scan(@_);
}

# ------------------------------------------------------------------------------
# reload - Force this node to reload itself
# reload
# ------------------------------------------------------------------------------

sub reload {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self);
  $tied->__mtime(0);
  $tied->__checkpoint(0);
  $tied->__scan;
}

sub free {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self);
  $tied->__checkpoint(0);
  $tied->__mtime(0);
  %{$tied->__data} = ();
  %{$tied->__private} = ();
  $tied->___content('');
  $tied->__raw_content('');
}

# ------------------------------------------------------------------------------
# is_valid - Are we still a valid handler for this path?
# ------------------------------------------------------------------------------

sub is_valid {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self);
  # only check once per request (must happen for any call to __scan)
  return 1 if defined $tied->__checkpoint
    && $tied->__checkpoint >= ${$tied->__global_cp};
  isa($self, Get_Pkg($tied->__path));
}

# ==============================================================================
# Tie interface
#
# Note ___content is the same as __content, however it should not be
# overridden in derived classes, allowing the __content method to literally
# set the scalar value.
# ==============================================================================

sub __data        { exists $_[1] ? $_[0][0]    = $_[1] : $_[0][0] }
sub __content     { exists $_[1] ? $_[0][1]    = $_[1] : $_[0][1] }
sub ___content    { exists $_[1] ? $_[0][1]    = $_[1] : $_[0][1] } # See above
sub __meta        { exists $_[1] ? $_[0][2]    = $_[1] : $_[0][2] }
sub __path        { exists $_[1] ? $_[0][2][0] = $_[1] : $_[0][2][0] }
sub __addr        { exists $_[1] ? $_[0][2][1] = $_[1] : $_[0][2][1] }
sub __hub         { exists $_[1] ? $_[0][2][2] = $_[1] : $_[0][2][2] }
sub __checkpoint  { exists $_[1] ? $_[0][2][3] = $_[1] : $_[0][2][3] }
sub __mtime       { exists $_[1] ? $_[0][2][4] = $_[1] : $_[0][2][4] }
sub __access_log  { exists $_[1] ? $_[0][2][5] = $_[1] : $_[0][2][5] }
sub __global_cp   { exists $_[1] ? $_[0][2][6] = $_[1] : $_[0][2][6] }
sub __disk_mtime  { exists $_[1] ? $_[0][2][7] = $_[1] : $_[0][2][7] }
sub __stat        { exists $_[1] ? $_[0][2][8] = $_[1] : $_[0][2][8] }
sub __change_log  { exists $_[1] ? $_[0][2][9] = $_[1] : $_[0][2][9] }
sub __private     { exists $_[1] ? $_[0][3]    = $_[1] : $_[0][3] }
sub __raw_content { exists $_[1] ? $_[0][4]    = $_[1] : $_[0][4] }

# ------------------------------------------------------------------------------
# TIEHASH - See C<perltie>
# TIEHASH $class, $path
# TIEHASH $class, $path, $stat
# TIEHASH $class, $path, $stat, $hub
# ------------------------------------------------------------------------------

sub TIEHASH {
  my $class = shift;
  my $path = shift or confess '$path';
  my $stat = shift;
  my $hub = shift;
  # TODO refactor for efficiency (path_to_addr)
  my $addr = $hub ? $hub->__path_to_addr($path) : undef;
  my $access_log = $hub ? $hub->__fs_access : Data::Hub::FileSystem::AccessLog->new();
  my $change_log = $hub ? $hub->__fs_change : Data::Hub::FileSystem::AccessLog->new();
  my $local_cp = 1; # must be greater-than zero for expire to work
  my $global_cp = $hub ? $hub->__req_count : \$local_cp;
  bless [
    Data::OrderedHash->new(), # __data
    undef, # __content
    [ # __meta
      $path, # __path
      $addr, # __addr
      $hub, # __hub
      undef, # __checkpoint
      undef, # __mtime
      $access_log, # __access_log
      $global_cp, # __global_cp
      undef, # __disk_mtime
      $stat, # __stat
      $change_log, # __change_log
    ],
    {}, # __private
    undef, # __raw_content
  ], $class;
}

# ------------------------------------------------------------------------------
# FIRSTKEY - See C<perltie>
# Scan for changes. This allows cached instances to refresh themselves upon 
# member access.
# ------------------------------------------------------------------------------

sub FIRSTKEY {
  my $tied = shift;
  $tied->__scan(undef, 1);
  $tied->SUPER::FIRSTKEY(@_)
}

# ------------------------------------------------------------------------------
# FETCH - See C<perltie>
# Scan for changes.
# ------------------------------------------------------------------------------

sub FETCH {
  $_[0]->__scan($_[1]);
  $_[0]->__data->{$_[1]};
}

# ------------------------------------------------------------------------------
# EXISTS - See C<perltie>
# Scan for changes.
# ------------------------------------------------------------------------------

sub EXISTS {
  $_[0]->__scan($_[1]);
  exists $_[0][0]->{$_[1]};
}

# ------------------------------------------------------------------------------
# STORE - See C<perltie>
# Scan for changes and update modified time.
# ------------------------------------------------------------------------------

sub STORE {
  $_[0]->__scan($_[1]);
  $_[0]->__mtime(int(time));
  $_[0]->__data->{$_[1]} = $_[2];
}

# ------------------------------------------------------------------------------
# DELETE - See C<perltie>
# Scan for changes and update modified time.
# ------------------------------------------------------------------------------

sub DELETE {
  $_[0]->__scan($_[1]);
  $_[0]->__mtime(int(time));
  delete $_[0]->__data->{$_[1]};
}

# ------------------------------------------------------------------------------
# SCALAR - See C<perltie>
# Scan for changes and return node contents.
# ------------------------------------------------------------------------------

sub SCALAR {
  $_[0]->__scan;
  $_[0]->__content;
}

# ------------------------------------------------------------------------------
# __read_from_disk - Read instance data from persistent storage
# __read_from_disk
# Base method.
# ------------------------------------------------------------------------------

sub __read_from_disk {
}

# ------------------------------------------------------------------------------
# __write_to_disk - Write instance data to persistent storage
# __write_to_disk
# Abstract base method.
# ------------------------------------------------------------------------------

sub __write_to_disk {
  throw Error::Programatic "Not a persitent object";
}

# ------------------------------------------------------------------------------
# __scan - Read from disk if necessary
# __scan
# __scan $key             # used only by directories
# __scan undef, 1         # used by directories to index into fs_access_log
#
# When C<$key> is provided, this resource is then instantiated if necessary.
# This allows L<Data::Hub::FileSystem::Directory> to maintain a key/value pair of
# filename/undef when reading the directory and delay instantiating (and hence
# recursively reading) the value until it is called upon.
# ------------------------------------------------------------------------------

sub __scan {
  my $reload = 1;
  my $stat = undef;
#$_[0]->__errlog( " <scan> " . $_[0]->__path . "\n");
  if (defined($_[0]->__checkpoint)) {
    # we have read the node before
    if ($_[0]->__checkpoint < ${$_[0]->__global_cp}) {
      # no global checkpoint set, or
      # we have not checked the node during this request
      if ($_[0]->__path && $_[0]->__mtime) {
        # the node existed the last time we read it
        # -1 to capture files modified in the same second
        $stat = stat $_[0]->__path;
#       my $last_checked = $_[0]->__mtime - 1;
#       my $last_modified = $stat->mtime;
#$_[0]->__errlog( " <rechk> $last_checked < $last_modified " . $_[0]->__path . "\n");
        $reload = $stat ? ($_[0]->__mtime - 1) < $stat->mtime : 0;
      } else {
        # Forced reload scenario
        $stat = stat $_[0]->__path;
      }
    } else {
      # we have checked the node during this request
      $stat = $_[0]->__stat;
      $reload = 0;
    }
  } else {
    # first read
#   $stat = stat $_[0]->__path;
#   $stat = $_[0]->__stat || stat $_[0]->__path;
    $stat = $_[0]->__stat;
    $reload = defined $stat;
  }
  if ($reload) {
#$_[0]->__errlog( "  <read> " . $_[0]->__path . "\n");
    # $stat must be defined at this point
    $_[0]->__stat($stat);
    $_[0]->__mtime(int(time));
    $_[0]->__disk_mtime($stat ? $stat->mtime : undef);
    $_[0]->__read_from_disk();
  }
  if (defined $stat) {
    $_[0]->__track() unless S_ISDIR($stat->mode) && !$_[2];
  }
  $_[0]->__checkpoint(${$_[0]->__global_cp});
  $reload;
}

sub __track {
#$_[0]->__errlog( "track:", $_[0]->__path, "\n");
  $_[0]->__access_log->set_value($_[0]->__path, $_[0]->__disk_mtime);
}

sub __track_change {
# $_[0]->__errlog( "track change:", $_[0]->__path, "\n");
  $_[0]->__change_log->set_value($_[0]->__path, $_[0]->__disk_mtime);
}

sub __errlog {
  my $tied = shift;
  my $hub = $tied->__hub;
  my $log = $hub ? $hub->__fetch('/sys/log') : undef;
  if ($log) {
    $log->info(@_);
  } else {
    warn @_;
  }
}

1;

package Data::Hub::FileSystem::Node::Crown;
use strict;
use Carp qw(croak confess);
use IO::File;
use Fcntl qw(:flock);
# ------------------------------------------------------------------------------
# The first 128 bytes of a file
# 
#   tie \$crown, Data::Hub::FileSystem::Node::Crown, $path;
#
#   - Reading from the file is delayed until needed.
#   - Subsequent calls re-use the read buffer.
#   - Will croak on directories.
#
# Underlying structure is an array
#
#   [0] - Path to file
#   [1] - Buffer size (default=128)
#   [2] - (reserved)
#   [3] - Buffer
# ------------------------------------------------------------------------------
sub TIESCALAR {
  my $pkg = shift;
  my $path = shift or confess 'No file path provided';
  my $len = shift || 128;
  bless [
    $path,
    $len,
    undef,
    undef,
  ], $pkg;
}
sub FETCH {
  return $_[0][3] if defined $_[0][3];
  my $buf = undef;
  {
#warn sprintf("READ [%d]: %s\n", time, $_[0][0]);
    if (my $h = IO::File->new('<' . $_[0][0])) {
      # Removing the locking call as waiting for a lock is hardly ideal when
      # simply trying to determine a file's type.  This method is called _very_
      # often. (2001-02-23)
      #flock $h, LOCK_SH or die $!;
      sysread $h, $buf, $_[0][1], 0;
    }
  }
  $_[0][3] = defined $buf ? $buf : '';
}
sub DESTROY {}
sub STORE {}
1;

__END__
