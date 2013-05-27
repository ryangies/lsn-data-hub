package Data::Hub::Util;
use strict;
our $VERSION = 0;

use Exporter qw(import);
use Perl::Module;
use Parse::StringTokenizer;
use Error::Simple;
use Error::Programatic;
use Encode;
use IO::File;
use IO::Dir;
use Fcntl qw(:flock);
use File::Copy qw();
use Data::Hub::Address;

our @EXPORT = qw();
our @EXPORT_OK = qw(
  RE_ABSTRACT_KEY
  RE_ABSTRACT_ADDR
  $VALUE_ALL
  $VALUE_ALL_REC
  $PATTERN_QUERY
  $PATTERN_QUERY_SUBKEY
  $PATTERN_QUERY_VALUE
  $PATTERN_QUERY_RANGE
  $PATTERN_QUERY_KEY
  %TYPEOF_ALIASES

  FS
  is_abstract_key
  is_abstract_addr
  curry
  typeof

  addr_shift
  addr_pop
  addr_normalize
  addr_parent
  addr_name
  addr_basename
  addr_split
  addr_join
  addr_ext
  addr_base

  path_shift
  path_pop
  path_push
  path_normalize
  path_parent
  path_name
  path_split
  path_join
  path_ext
  path_is_absolute
  path_basename

  fs_handle

  file_read
  file_read_binary
  file_read_crown
  file_create
  file_write
  file_write_binary
  file_copy
  file_move
  file_remove

  dir_read
  dir_create
  dir_copy
  dir_copy_contents
  dir_is_system
  dir_move
  dir_remove
);
our %EXPORT_TAGS = (
  all => [@EXPORT_OK],
);

# ------------------------------------------------------------------------------
#|test(!abort) use Data::Hub::Util qw(:all); # Load this module
# ------------------------------------------------------------------------------
sub RE_ABSTRACT_KEY         {qr/^\{|(?<!\\)[\*\|]/};
sub RE_ABSTRACT_ADDR        {qr/\/\{|(?<!\\)[\*\|]/};
our $VALUE_ALL              = q/*/;
our $VALUE_ALL_REC          = q/**/;
our $PATTERN_QUERY          = q/^\{(.*)\}$/;
our $PATTERN_QUERY_SUBKEY   = q/^([^'\s]+)\s+([^'\s]+)\s+(.*)$/;
our $PATTERN_QUERY_VALUE    = q/^([^\s]+)\s+'?(.+?)'?$/;
our $PATTERN_QUERY_RANGE    = q/^([\d\-,]+)$/;
our $PATTERN_QUERY_KEY      = q/^'?(.*?)'?$/;

# ------------------------------------------------------------------------------
# is_abstract_key - Is the key abstract (produces a subset)
# is_abstract_key $key
#
# TODO The regex RE_ABSTRACT_KEY uses an error-prone search for | and * (these
# are allowed in hashfile key names.
# ------------------------------------------------------------------------------

sub is_abstract_key {
  return unless defined $_[0];
  $_[0] =~ RE_ABSTRACT_KEY;
}

# ------------------------------------------------------------------------------
# is_abstract_addr - Does the address contain an abstract key
# is_abstract_addr $addr
# ------------------------------------------------------------------------------

sub is_abstract_addr {
  return unless defined $_[0];
  $_[0] =~ RE_ABSTRACT_ADDR;
}

# ------------------------------------------------------------------------------
# curry - Add the courier magic to the provided reference
# curry \%thingy
# curry \@thingy
# ------------------------------------------------------------------------------
#|test(match,c) curry({a=>{b=>'c'}})->get('/a/b');
# ------------------------------------------------------------------------------

sub curry {
  require Data::Hub::Container;
  goto \&Data::Hub::Container::Bless;
}

# ------------------------------------------------------------------------------
# FS - Return the package name for the given file-system class
# FS $class
# ------------------------------------------------------------------------------
#|test(match,Data::Hub::FileSystem::Node) FS('Node');
# ------------------------------------------------------------------------------

sub FS {
  "Data::Hub::FileSystem::$_[0]";
}

# ------------------------------------------------------------------------------
# typeof - Return the logical type for the given file-system or data structure
# typeof $name, $struct
# ------------------------------------------------------------------------------
#|test(match,data-hash) typeof('foo.bar', {});
#|test(match,data-array) typeof('/with/path/foo.bar', []);
#|test(match,data-scalar-bar) typeof('foo.bar', 'baz');
# ------------------------------------------------------------------------------

our %TYPEOF_ALIASES = (
  d => 'directory',
  f => '!~^(?:data-|directory|code)',
  t => '=~^file-(?:multipart|text)-',
  h => 'data-hash',
  a => 'data-array',
  c => 'code',
  s => '=~^data-scalar',
  H => 'file-data-hash',
  M => '=~^file-multipart-',
  T => '=~^file-text',
  D => '=~^data-',
);

sub typeof {
  my ($name, $struct) = @_;
  return unless defined $name;
  return unless defined $struct;
  my $type = undef;
  if (isa($struct, FS('Node'))) {
    if (isa($struct, FS('Directory'))) {
      $type = 'directory';
    } else {
      $type = 'file';
      if (isa($struct, FS('HashFile'))) {
        $type .= '-data-hash';
      } else {
        my $ext = path_ext($name);
        if (isa($struct, FS('TextFile'))) {
          $type .= $struct->length ? '-multipart' : '-text';
        } else {
          $type .= '-multipart' if $struct->length;
        }
        $ext and $type .= "-$ext";
      }
    }
  } elsif (isa($struct, 'CODE')) {
    $type = 'code';
  } else {
    $type = 'data';
    if (isa($struct, 'HASH')) {
      $type .= '-hash';
    } elsif (isa($struct, 'ARRAY')) {
      $type .= '-array';
    } else {
      $type .= '-scalar';
      if (my $ext = path_ext($name)) {
        $type .= "-$ext";
      }
    }
  }
# warn "typeof: $name is $type\n";
  lc($type);
}

# ------------------------------------------------------------------------------
# Package variables
# ------------------------------------------------------------------------------

our $Path_Tokenizer = Parse::StringTokenizer->new(
  -delim      => q(/),
);

our $Addr_Tokenizer = Parse::StringTokenizer->new(
  -contained  => q({}),
  -quotes     => q('"),
  -delim      => q(/),
);

# ------------------------------------------------------------------------------
# addr_shift - Return the next token and trim the address
# addr_shift $addr
# ------------------------------------------------------------------------------
#|test(match)
#|my $addr = '/one/two/{/i/am/three}/four';
#|join(':', addr_shift($addr), addr_shift($addr), addr_shift($addr),
#|  addr_shift($addr)); 
#=one:two:{/i/am/three}:four
# ------------------------------------------------------------------------------

sub addr_shift(\$) { $Addr_Tokenizer->shift($_[0]) }

# ------------------------------------------------------------------------------
# addr_pop - Return the last token and trim the address
# addr_pop $addr
# ------------------------------------------------------------------------------
#|test(match)
#|my $addr = '/one/two';
#|my $last = addr_pop($addr);
#|"$last,$addr"
#=two,/one
# ------------------------------------------------------------------------------

sub addr_pop(\$) { return $Addr_Tokenizer->pop($_[0]) }

# ------------------------------------------------------------------------------
# addr_normalize - Normalize form of the given address 
# addr_normalize $addr
# See also L</_normalize>
# ------------------------------------------------------------------------------
#|test(match,/)             addr_normalize('/');
#|test(match,/a)            addr_normalize('/a/');
#|test(match,/a)            addr_normalize('/a/b/..');
#|test(match,/b)            addr_normalize('/a/../b');
#|test(match,/b)            addr_normalize('/a/../../b');
#|test(match,/a)            addr_normalize('/a/.../b');
#|test(match,/a)            addr_normalize('/a/.../');
#|test(match,/a)            addr_normalize('/a/...');
#|test(match,/a)            addr_normalize('/a/.../..');
#|test(match,/)             addr_normalize('/a/../...');
# ------------------------------------------------------------------------------

sub addr_normalize {
  _normalize($_[0], $Addr_Tokenizer);
}

# ------------------------------------------------------------------------------
# addr_parent - Return the parent of the given address
# addr_parent $addr
# ------------------------------------------------------------------------------
#|test(!defined)            addr_parent();
#|test(!defined)            addr_parent('');
#|test(match,/)             addr_parent('/');
#|test(match,/)             addr_parent('/a');
#|test(match,/)             addr_parent('/a/b/..');
#|test(match,a)             addr_parent('a/b/');
#|test(match,a)             addr_parent('a/b.c');
# ------------------------------------------------------------------------------

sub addr_parent {
  my $addr = addr_normalize(shift) or return;
  my $is_abs = index($addr, '/') == 0;
  $Addr_Tokenizer->pop(\$addr);
  $addr or $is_abs ? '/' : $addr;
}

# ------------------------------------------------------------------------------
# addr_name - Return the name part of an address
# ------------------------------------------------------------------------------
#|test(!defined)            addr_name('');
#|test(match,)              addr_name('/');
#|test(match,a)             addr_name('/a');
#|test(match,a)             addr_name('/a/b/..');
#|test(match,b)             addr_name('a/b/');
#|test(match,b.c)           addr_name('a/b.c');
# ------------------------------------------------------------------------------

sub addr_name($) {
  my $s = addr_normalize(shift);
  return unless defined $s;
  $Addr_Tokenizer->pop(\$s);
}

# ------------------------------------------------------------------------------
# addr_split - Return each part of an address
# ------------------------------------------------------------------------------
#|test(match,0)             scalar(addr_split(''));
#|test(match,)              join ' ', addr_split('/');
#|test(match,a)             join ' ', addr_split('/a');
#|test(match,a)             join ' ', addr_split('/a/b/..');
#|test(match,a b)           join ' ', addr_split('a/b/');
#|test(match,a b.c)         join ' ', addr_split('a/b.c');
# ------------------------------------------------------------------------------

sub addr_split($) {
  my $s = addr_normalize(shift);
  return unless defined $s;
  $Addr_Tokenizer->split(\$s);
}

# ------------------------------------------------------------------------------
# addr_join - Normalize form of the given address 
# addr_join $addr
# See also L</_normalize>
# ------------------------------------------------------------------------------
#|test(match,/)             addr_join('/');
#|test(match,/a)            addr_join('/a', '/');
#|test(match,/a)            addr_join('/a/', 'b/..');
#|test(match,/b)            addr_join('/a/..', '/b');
#|test(match,/b)            addr_join('/a/../', '../b');
#|test(match,/a)            addr_join('/a/.../', 'b');
#|test(match,/a)            addr_join('/a/', '.../');
#|test(match,/a)            addr_join('/a/', '...');
#|test(match,/a/b)          addr_join('/a/', 'b/');
#|test(match,/a/b)          addr_join('/a/', 'b');
#|test(match,/a/b)          addr_join('/a', '/b');
#|test(match,/a/b)          addr_join('/a', 'b');
#|test(match,/a/b/c)        addr_join('/a', 'b', 'c');
# ------------------------------------------------------------------------------

sub addr_join {
  _normalize(join('/', @_), $Addr_Tokenizer);
}

# ------------------------------------------------------------------------------
# addr_ext - Return the extension part of the given address
# addr_ext $path
# ------------------------------------------------------------------------------
#|test(!defined)            addr_ext(undef);
#|test(match,txt)           addr_ext('foo.txt');
#|test(match,txt)           addr_ext('/foo.txt');
#|test(match,txt)           addr_ext('./foo.txt');
#|test(match,txt)           addr_ext('../foo.txt');
#|test(match,txt)           addr_ext('/foo/foo.txt');
#|test(match,txt)           addr_ext('/foo.bar.txt');
#|test(match,)              addr_ext('/foo/bar.');
#|test(!defined)            addr_ext('/foo/bar');
#|test(!defined)            addr_ext('.metadata');
#|test(match,bak)           addr_ext('.metadata.bak');
# ------------------------------------------------------------------------------

sub addr_ext($) {
  my $s = addr_normalize(shift);
  return unless defined $s;
  my $name = $Addr_Tokenizer->pop(\$s);
  $name =~ s/.+\.// ? $name : undef;
}

# ------------------------------------------------------------------------------
# addr_basename - Return the name at the given address without its extension
# addr_basename $addr
# ------------------------------------------------------------------------------
#|test(!defined)            addr_basename(undef);
#|test(!defined)            addr_basename('/');
#|test(match,foo)           addr_basename('foo.txt');
#|test(match,foo)           addr_basename('foo.txt/');
#|test(match,foo)           addr_basename('/foo.txt');
#|test(match,foo)           addr_basename('./foo.txt');
#|test(match,foo)           addr_basename('../foo.txt');
#|test(match,foo)           addr_basename('/foo/foo.txt');
#|test(match,foo.bar)       addr_basename('/foo.bar.txt');
#|test(match,bar)           addr_basename('/foo/bar.');
#|test(match,bar)           addr_basename('/foo/bar');
#|test(!defined)            addr_basename('.metadata');
#|test(match,.metadata)     addr_basename('.metadata.bak');
# ------------------------------------------------------------------------------

sub addr_basename($) {
  my $s = addr_normalize(shift);
  return unless defined $s;
  my $name = $Addr_Tokenizer->pop(\$s);
  $name =~ s/\.[^\.]*$//;
  $name || undef;
}

# ------------------------------------------------------------------------------
# addr_base - Return the base (known part) of the given address
# addr_base $addr
# ------------------------------------------------------------------------------
#|test(match,/a/b)          addr_base('/a/b/{d}');
#|test(match,/a/b/d)        addr_base('/a/b/d');
# ------------------------------------------------------------------------------

sub addr_base($) {
  my $a = Data::Hub::Address->new(shift);
  for (my $i = 0; $i < @$a; $i++) {
    my $k = $a->[$i];
    if (is_abstract_key($k)) {
      # Filters (pipes) are refinements to a key, so keep the key portion.
      if ($k =~ s/\|.*//) {
        $a->[$i] = $k;
      } else {
        splice @$a, $i;
      }
      last;
    }
  }
  $a->to_string();
}

# ------------------------------------------------------------------------------
# path_shift - Return the next token and trim the path
# path_shift $path
# ------------------------------------------------------------------------------
#|test(match)
#|my $path = '/one/two/../four';
#|join(':', path_shift($path), path_shift($path), path_shift($path),
#|  path_shift($path)); 
#=one:two:..:four
# ------------------------------------------------------------------------------

sub path_shift(\$) { $Path_Tokenizer->shift($_[0]) }

# ------------------------------------------------------------------------------
# path_pop - Return the last token and trim the path
# path_pop $path
# ------------------------------------------------------------------------------
#|test(match)
#|my $path = '/one/two';
#|my $last = path_pop($path);
#|"$last,$path"
#=two,/one
# ------------------------------------------------------------------------------

sub path_pop(\$) { $Path_Tokenizer->pop($_[0]) }

# ------------------------------------------------------------------------------
# path_push - Push a token on to the path
# path_push $path
# ------------------------------------------------------------------------------
#|test(match)
#|my $path = '/one/two';
#|my $count = path_push($path, 'three');
#|"$path"
#=/one/two/three
# ------------------------------------------------------------------------------

sub path_push(\$$) { $Path_Tokenizer->push($_[0], $_[1]) }

# ------------------------------------------------------------------------------
# path_split - Return each part of a path
# ------------------------------------------------------------------------------
#|test(match,0)             path_split('');
#|test(match,)              join ' ', path_split('/');
#|test(match,a)             join ' ', path_split('/a');
#|test(match,a)             join ' ', path_split('/a/b/..');
#|test(match,a b)           join ' ', path_split('a/b/');
#|test(match,a b.c)         join ' ', path_split('a/b.c');
# ------------------------------------------------------------------------------

sub path_split($) {
  my $s = path_normalize(shift);
  return unless defined $s;
  $Path_Tokenizer->split(\$s);
}

sub path_join {
  _normalize(join('/', @_), $Path_Tokenizer);
}

# ------------------------------------------------------------------------------
# path_basename - Return the name part of the given path without its extension
# path_basename $path
# ------------------------------------------------------------------------------
#|test(!defined)            path_basename(undef);
#|test(match,foo)           path_basename('foo.txt');
#|test(match,foo)           path_basename('/foo.txt');
#|test(match,foo)           path_basename('./foo.txt');
#|test(match,foo)           path_basename('../foo.txt');
#|test(match,foo)           path_basename('/foo/foo.txt');
#|test(match,foo.bar)       path_basename('/foo.bar.txt');
#|test(match,bar)           path_basename('/foo/bar.');
#|test(match,bar)           path_basename('/foo/bar');
#|test(match,.bashrc)       path_basename('.bashrc');
#|test(match,.bashrc)       path_basename('.bashrc.tmp');
#|test(match,no-dots)       path_basename('/no-dots');
# ------------------------------------------------------------------------------

sub path_basename($) {
  my $s = path_normalize(shift);
  return unless defined $s;
  my $name = $Path_Tokenizer->pop(\$s);
  return unless defined $name;
  my $basename = $name;
  my ($ext) = $basename =~ s/\.([^\.]*)$//;
  $basename || $name;
}

# ------------------------------------------------------------------------------
# path_ext - Return the extension part of the given path
# path_ext $path
# ------------------------------------------------------------------------------
#|test(!defined)            path_ext(undef);
#|test(match,txt)           path_ext('foo.txt');
#|test(match,txt)           path_ext('/foo.txt');
#|test(match,txt)           path_ext('./foo.txt');
#|test(match,txt)           path_ext('../foo.txt');
#|test(match,txt)           path_ext('/foo/foo.txt');
#|test(match,txt)           path_ext('/foo.bar.txt');
#|test(match,)              path_ext('/foo/bar.');
#|test(!defined)            path_ext('/foo/bar');
#|test(!defined)            path_ext('.bashrc');
#|test(match,tmp)           path_ext('.bashrc.tmp');
#|test(!defined)            path_ext('/no-dots');
# ------------------------------------------------------------------------------

sub path_ext($) {
  my $s = path_normalize(shift);
  return unless defined $s;
  my $name = $Path_Tokenizer->pop(\$s);
  return unless defined $name;
  $name =~ s/.+\.// ? $name : undef;
}

# ------------------------------------------------------------------------------
# path_normalize - Normalize form of the given path
# path_normalize $path
# See also L</_normalize>
# ------------------------------------------------------------------------------
#|test(match,/)             path_normalize('/');
#|test(match,/a)            path_normalize('/a/');
#|test(match,/a)            path_normalize('/a/b/..');
#|test(match,/a)            path_normalize('/a/../a');
#|test(match,/a)            path_normalize('/a/../../a');
#|test(match,../../w/s/x)   path_normalize( "../../w/b/../s/x" );
#|test(match,u/n/w)         path_normalize( "u/n/w/" );
#|test(match,w/s)           path_normalize( "u/../w/b/../s" );
#|test(match,u/n)           path_normalize( "u//n" );
#|test(match,u/n/f)         path_normalize( "u//n/./f" );
#|test(match,http://t/u/n)  path_normalize( "http://t/u//n" );
#|test(match,/d/e/f)        path_normalize( '/a/b/c/../../../d/e/f' );
#|test(match,./a)           path_normalize( './a' );
#|test(match,/a)            path_normalize( '/./a' );
#-------------------------------------------------------------------------------

sub path_normalize($@) {
  _normalize($_[0], $Path_Tokenizer);
}

# ------------------------------------------------------------------------------
# _normalize - Implementation method for L<addr_normalize> and L<path_normalize>
# _normalize $path, $tokenizer
# ------------------------------------------------------------------------------

sub _normalize($@) {
  my $path = shift;
  my $tokenizer = shift;
  return unless defined $path;
  my ($left, $right) = $path =~ /^([A-Za-z\+]+:\/{2}|\/|(?:\.{2}\/)+)?(.*)/;
  my $result = '';
  my @items = $tokenizer->split($right);
  for (my $i = 0; $i < @items; $i++) {
    if ($items[$i] eq '...') {
      splice @items, $i, 2;
    } elsif ($items[$i] eq '..') {
      splice @items, $i--, 1;
      $i >= 0 and splice @items, $i--, 1;
    } elsif ($items[$i] eq '.') {
      splice (@items, $i--, 1) unless ($i == 0 && !$left);
    }
  }
# $right = join('/', @items);
  $right = $tokenizer->pack(@items);
  $left ? $left . $right : $right;
}

# ------------------------------------------------------------------------------
# path_parent - Return the parent of the given path
# path_parent $path
# ------------------------------------------------------------------------------
#|test(!defined)            path_parent('');
#|test(match,/)             path_parent('/');
#|test(match,/)             path_parent('/a');
#|test(match,/)             path_parent('/a/b/..');
#|test(match,)              path_parent('a');
#|test(match,a)             path_parent('a/b/');
#|test(match,a)             path_parent('a/b.c');
#|test(match,../..)         path_parent('../../a');
# ------------------------------------------------------------------------------

sub path_parent($) {
  my $path = path_normalize($_[0]) or return;
  $Path_Tokenizer->pop(\$path);
  $path || ($_[0] =~ /^\// ? '/' : $path);
}

# ------------------------------------------------------------------------------
# path_name - Return the name part of a path
# ------------------------------------------------------------------------------
#|test(!defined)            path_name('');
#|test(match,)              path_name('/');
#|test(match,a)             path_name('/a');
#|test(match,a)             path_name('/a/b/..');
#|test(match,b)             path_name('a/b/');
#|test(match,b.c)           path_name('a/b.c');
# ------------------------------------------------------------------------------

sub path_name($) {
  my $s = path_normalize(shift);
  return unless defined $s;
  $Path_Tokenizer->pop(\$s);
}

# ------------------------------------------------------------------------------
# path_is_absolute - Is the path an absolute path
# ------------------------------------------------------------------------------
#|test(true)                path_is_absolute('/a');
#|test(true)                path_is_absolute('A:/b');
#|test(true)                path_is_absolute('/a/b');
#|test(true)                path_is_absolute('http://a');
#|test(true)                path_is_absolute('svn+ssh://a.b');
#|test(false)               path_is_absolute('');
#|test(false)               path_is_absolute('a/b');
#|test(false)               path_is_absolute('a:\\b');
#|test(false)               path_is_absolute('a/../b');
#|test(false)               path_is_absolute('../a');
#|test(false)               path_is_absolute('./a');
#|test(false)               path_is_absolute('svn+ssh//a.b');
#|test(false)               path_is_absolute('1://');
#|test(false)               path_is_absolute('+://');
# ------------------------------------------------------------------------------

sub path_is_absolute {
  $_[0] && $_[0] =~ /^([A-Za-z][A-Za-z\+]*:\/{1,2}|\/)/;
}

# ------------------------------------------------------------------------------
# dir_read - Return directory entries
# dir_read $path
# ------------------------------------------------------------------------------

sub dir_read {
  my $dir = shift or return ();
  my $h = fs_handle($dir) or croak "$!: $dir";
  opendir ($h, $dir) or die "$!: $dir";
  my @entries = map {Encode::decode('utf8', $_)} sort grep ! /^\.+$/, readdir $h;
  closedir $h;
  return @entries;
}

# ------------------------------------------------------------------------------
# file_read - Read file contents
# ------------------------------------------------------------------------------

sub file_read {
  my $path = shift or return;
  my $h = fs_handle($path, 'r') or croak "$!: $path";
  binmode $h, ':encoding(utf8)';
  my $contents = '';
  {
    local $/ = undef; # slurp
    $contents = <$h>;
  }
  return \$contents;
}

# ------------------------------------------------------------------------------
# file_read_binary - Read file contents (binary)
# ------------------------------------------------------------------------------

sub file_read_binary {
  my $path = shift or return;
  my $h = fs_handle($path, 'r') or croak "$!: $path";
# flock $h, LOCK_SH or die $!;
  binmode $h;
  my $contents = undef;
  {
    local $/ = undef; # slurp
    $contents = <$h>;
  }
# close $h;
  return unless defined $contents;
  return \$contents;
}

# ------------------------------------------------------------------------------
# file_create - Create an empty file if none exists
# file_create $path
# ------------------------------------------------------------------------------

sub file_create {
  my $path = shift or return;
  file_write($path, '') unless -e $path;
}

# ------------------------------------------------------------------------------
# file_write - Write contents to file
# file_write $path, @contents
#
# where:
#
#   @contents           Items may be scalars or scalar references
#
# returns:
#
#   1 when successful
#   dies if a handle cannot be obtained
# ------------------------------------------------------------------------------

sub file_write($@) {
  my $path = shift or return;
  my $parent = path_parent($path);
  dir_create($parent) if $parent && !-e $parent;
  my $h = fs_handle($path, 'w') or die "$!: $path";
  binmode $h, ':utf8';
  for (@_) {
    next unless defined;
    my $s = isa($_, 'SCALAR') ? $_ : \$_;
#   utf8::decode($$s);
    print $h $$s;
  }
  close $h;
  return 1;
}

# ------------------------------------------------------------------------------
# file_write_binary - Write contents to file (binary)
# file_write_binary $path, @contents
#
# where:
#
#   @contents           Items may be scalars or scalar references
#
# returns:
#
#   1 when successful
#   dies if a handle cannot be obtained
# ------------------------------------------------------------------------------

sub file_write_binary($@) {
  my $path = shift or return;
  my $parent = path_parent($path);
  dir_create($parent) if $parent && !-e $parent;
  my $h = fs_handle($path, 'w') or die "$!: $path";
  binmode $h;
  for (@_) {
    print $h isa($_, 'SCALAR') ? $$_ : $_;
  }
  close $h;
  return 1;
}

# ------------------------------------------------------------------------------
# file_read_crown - Return the first line of a file
# file_read_crown $path
# ------------------------------------------------------------------------------

sub file_read_crown {
  my $path = shift or return;
  return unless -f $path;
  my $crown = undef;
  my $h = fs_handle($path, 'r') or die "$!: $path";
  if (-T $path) {
    $crown = <$h>;
  } else {
    my $buf = undef;
    read $h, $buf, 1024;
    if (defined $buf) {
      ($crown) = $buf =~ /^([^\r\n]+)/;
    }
  }
  close $h;
  $crown;
}

# ------------------------------------------------------------------------------
# fs_handle - Return a file or directory handle
# fs_handle $path
# fs_handle $path, $mode
#
# where:
#
#   $path           # Absolute or relative file-system path
#   $mode   r|w|rw  # Read or write access (default 'r')
# ------------------------------------------------------------------------------

sub fs_handle($@) {
  my $path = shift or die 'Provide a path';
  if (-d $path) {
    my $h = IO::Dir->new($path) or die "$!: $path";
    return $h;
  }
  my $flag = shift || 'r';
  if ($flag eq 'w') {
     my $h = IO::File->new('>>' . $path) or croak "$!: $path";
     flock $h, LOCK_EX or die $!;
     truncate $h, 0 or die $!;
     return $h;
  } elsif ($flag eq 'rw') {
     my $h = IO::File->new('+<' . $path) or croak "$!: $path";
     flock $h, LOCK_EX or die $!;
     return $h;
  } else {
     my $h = IO::File->new('<' . $path) or croak "$!: $path";
     flock $h, LOCK_SH or die $!;
     return $h;
  }
}

# ------------------------------------------------------------------------------
# dir_create - Create directory including parents
# ------------------------------------------------------------------------------

sub dir_create($) {
  my $path = shift or die 'Provide a path';
  my $dir = $path =~ /^\// ? '/' : '';
  my $count = 0;
  while(my $segment = $Path_Tokenizer->shift(\$path)) {
    $dir .= $segment;
    if (! -d $dir) {
      throw Error::Simple "Destination exists and is not a directory: $dir"
        if -e $dir;
      mkdir $dir or throw Error::Simple "$!: $dir";
      $count++;
    }
    $dir .= '/';
  }
  $count;
}

# ------------------------------------------------------------------------------
# file_copy - Copy a file
# file_copy $from_path, $to_path
# See also: L<File::Copy::copy>
# ------------------------------------------------------------------------------

sub file_copy($$) {
  File::Copy::copy(@_);
}

# ------------------------------------------------------------------------------
# file_move - Move a file
# file_move $from_path, $to_path
# See also: L<File::Copy::move>
# ------------------------------------------------------------------------------

sub file_move($$) {
  File::Copy::move(@_);
}

# ------------------------------------------------------------------------------
# dir_copy - Copy a directory recursively
# dir_copy $from_path, $to_path
# ------------------------------------------------------------------------------

sub dir_copy($$) {
  my $src_path = shift;
  my $out_path = shift;
  throw Error::Simple "Source directory does not exist: $src_path" unless -d $src_path;
  throw Error::Simple "Destination exists and is not a directory: $out_path"
    if -e $out_path && ! -d $out_path;
  -d $out_path and $out_path .= '/' . path_name($src_path);
  dir_create($out_path) unless -d $out_path;
  &dir_copy_contents($src_path, $out_path);
}

# ------------------------------------------------------------------------------
# dir_copy_contents - Copy a directory's contents recursively
# dir_copy_contents $from_path, $to_path
# ------------------------------------------------------------------------------

sub dir_copy_contents($$) {
  my ($src, $dest) = @_;
  for (dir_read($src)) {
    next if dir_is_system($_, $src);
    my $from = $src . '/' . $_;
    my $to = $dest .  '/' . $_;
    if (-d $from) {
      dir_create($to);
      &dir_copy_contents($from, $to);
    } else {
      file_copy($from, $to);
    }
  }
}

# ------------------------------------------------------------------------------
# dir_is_system - The directory is a system folder, such as '.svn'
# dir_is_system $name, $path
# ------------------------------------------------------------------------------
#|test(true)  dir_is_system('.svn', '/tmp'); # normal usage
#|test(true)  dir_is_system('.git', '/tmp'); # normal usage
#|test(false) dir_is_system('.Svn', '/tmp'); # case sensitive
#|test(!defined) dir_is_system(undef, undef); # undefined test
# ------------------------------------------------------------------------------

sub dir_is_system ($$) {
  my ($name, $path) = @_;
  return unless defined $name;
  return 1 if $name eq '.svn';
  return 1 if $name eq '.git';
  return 0;
}

# ------------------------------------------------------------------------------
# dir_move - Move a directory
# dir_move $from_path, $to_path
# See also: L<File::Copy::move>
# ------------------------------------------------------------------------------

sub dir_move($$) {
  File::Copy::move(@_)
    or throw Error::Simple sprintf("$!: while moving '%s' to '%s'", @_);
}

# ------------------------------------------------------------------------------
# file_remove - Remove a file
# file_remove $path
# ------------------------------------------------------------------------------

sub file_remove {
  my $sz = scalar(@_);
  my $cnt = unlink @_;
  if ($cnt != $sz) {
    for (@_) {
      warnf('Cannot remove: %s', $_) if -e $_;
    }
  }
  $cnt;
}

# ------------------------------------------------------------------------------
# dir_remove - Remove a directory recursively
# dir_remove $path
# ------------------------------------------------------------------------------

sub dir_remove($) {
  my $dir = shift;
  return unless -d $dir;
  for (dir_read($dir)) {
    my $entry = $dir . '/' . $_;
    if (! -l $entry && -d $entry) {
      &dir_remove($entry);
    } else {
      file_remove($entry);
    }
  }
  my $rc = rmdir $dir;
  warn "$!: $dir" unless $rc;
  $rc;
}

1;

__END__

# addr_to_path
# path_to_addr
# path_absolute
# path_relative
