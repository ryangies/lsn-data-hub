package Data::Hub::FileSystem::Directory;
use strict;
use Perl::Module;
use Data::Hub::Util qw(:all);
use Data::Hub::FileSystem::Node;
use base qw(Data::Hub::FileSystem::Node);

# Interface Data::Hub::Container

sub vivify {
  my $self = shift;
  my $tied = tied(%$self);
  $tied->FETCH($_[0]) || $tied->__vivify(@_);
}

# OO interface Data::Hub::FileSystem::Node

sub save {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $tied = tied(%$self);
  if ($tied->__path && ! -e $tied->__path) {
    dir_create($tied->__path);
    my $stat = stat $tied->__path or die "No stat create directory";
    $tied->__stat($stat);
    $tied->__mtime(int(time));
    $tied->__disk_mtime($stat ? $stat->mtime : undef);
    $tied->__track_change();
  }
  if ($tied->__private->{deleted}) {
    while (my $node = shift @{$tied->__private->{deleted}}) {
      my $path = $node->get_path;
      file_remove $path if $node->isa(FS('File'));
      dir_remove $path if $node->isa(FS('Directory'));
      die "Resource not removed: $node ($!): " . $path if -e $path;
      tied(%$node)->__track_change();
    }
  }
  $self;
}

sub rename_entry {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $old_name = shift;
  throw Error::IllegalArg unless defined($old_name);
  my $new_name = shift;
  throw Error::IllegalArg unless defined($new_name);
  my $node = $$self{$old_name} or throw Error::Logical 'Node does not exist';
  if ($node->rename($new_name)) {
    my $tied = tied(%$self);
    my $data = $tied->__data;
    delete $$data{$old_name};
    $data->{$new_name} = $node;
    $data->sort_by_key(sub {$_[0] cmp $_[1]}); # sort alphabetically
    my $stat = stat $tied->__path or die "No stat after rename_entry";
    $tied->__stat($stat);
    $tied->__mtime(int(time));
    $tied->__disk_mtime($stat ? $stat->mtime : undef);
  }
  $node;
}

# Tie interface Data::Hub::FileSystem::Node

sub __read_from_disk {
  my $self = shift;
  my $data = $self->__data;
  unless ($self->__path && -d $self->__path) {
    %$data = (); # clear
    return;
  }
  my %missing = map {($_, 1)} keys %$data;
  my $path = $self->__path;
  for (dir_read($path)) {
    next if dir_is_system($_, $path); # system folders such as '.svn'
    delete $missing{$_};
    next if exists $$data{$_};
    $$data{$_} = undef; # key now exists
  }
  delete $$data{$_} for (keys %missing);
  $data->sort_by_key(sub {$_[0] cmp $_[1]}); # sort alphabetically
}

sub __vivify {
  my $tied = shift;
  my $key = shift or return;
  my $default = shift || __PACKAGE__;
  my $path = ($tied->__path . '/' . $key);
  my $handler = Data::Hub::FileSystem::Node::Get_Pkg($path, $default);
  my $result = $tied->__data->{$key} = $handler->new($path, $tied->__hub);
  $tied->__data->sort_by_key(sub {$_[0] cmp $_[1]}); # sort alphabetically
  $result;
}

sub FETCH {
  $_[0]->__scan($_[1]);
  my $data = $_[0]->__data or throw Error::Programatic;
  return unless exists $$data{$_[1]};
  if (!defined($data->{$_[1]})) {
    my $path = $_[0]->__path . '/' . $_[1];
    $data->{$_[1]} = Data::Hub::FileSystem::Node->new($path, $_[0]->__hub);
  }
  $data->{$_[1]};
}

sub STORE {
  my $tied = shift;
  my $key = shift;
  my $value = shift;
  $tied->__scan($_[1]);
  my $data = $tied->__data;
  # Mark ourselves as modified
  $tied->__mtime(int(time));
  # Store a new FS object
  if (isa($value, FS('Node'))) {
#warn "vivify: $key\n";
    my $new = $tied->__vivify($key, ref($value));
    my $c = $value->get_raw_content();
    if ($c && $$c) {
#warn "c: $$c\n";
#warn "set: $key\n";
      $new->set_content(str_ref($$c)); # copy
    }
    return $new;
  }
  # Vivify new nodes
  unless (defined($tied->FETCH($key))) {
    my $default_pkg = FS('TextFile');
    $tied->__vivify($key, $default_pkg);
  }
  # Set value
  if (isa($$data{$key}, FS('Node'))) {
    my $node = $$data{$key};
    if (_is_scalar($value)) {
      $node->set_content($value);
    } else {
      $node->set_data($value);
    }
  } else {
    # Allow non-persistant data
    $$data{$key} = $value;
  }
  #$value;
  $$data{$key};
}

sub DELETE {
  my $node = $_[0]->FETCH($_[1]) or return;
  $_[0]->__private->{deleted} ||= [];
  push @{$_[0]->__private->{deleted}}, $node;
  delete $_[0]->__data->{$_[1]};
}

sub SCALAR {
  my $data = $_[0]->__data or return;
  join $/, keys %$data;
}

sub _is_scalar {
  !ref($_[0]) || isa($_[0], 'SCALAR');
}

sub __scan {
  my $tied = shift;
  my $reload = $tied->SUPER::__scan(@_);
  if (my $key = shift) {
    if (my $node = $tied->__data->{$key}) {
      unless ($node->is_valid) {
        $tied->__data->{$key} = FS('Node')->new($node->get_path, $tied->__hub);
      }
    }
  }
  return $reload;
}

1;

__END__
