package App::TMS::Client;
use strict;
our $VERSION = 0;

use Perl::Module;
use List::Util qw(max);
use Error qw(:try);
use Error::Simple;
use Error::Programatic;
use Data::Hub;
use Data::Hub::FileSystem::Node;
use Data::Format::Hash qw(hf_format);
use Data::Comparison qw();
use Data::OrderedHash;
use Parse::Template::Standard;
use Data::Hub::Util qw(:all);
use App::TMS::Common;
use App::TMS::Debug;
use base 'App::Console::CommandScript';
use Cwd qw(cwd);
use File::Spec qw(rel2abs file_name_is_absolute);

our %USAGE = ();

# ------------------------------------------------------------------------------
# new - Construct a new instance
# new
# ------------------------------------------------------------------------------

sub new {
  my $classname = shift;
  my $client_dir = shift;
  my $client = Data::Hub->new($client_dir);
  my $repo_dir = $client->{"$TMS_SETTINGS/repo_dir"};
  my $repo = undef;
  try {
    if ($repo_dir) {
      my $abs = path_is_absolute($repo_dir) ? $repo_dir : path_join(cwd(), $repo_dir);
      $repo = Data::Hub->new($abs);
    }
  } catch Error::Simple with {
    warnf "Current repository is invalid ($@): %s\n", $repo_dir;
  };
  bless {repo=>$repo, client=>$client}, ref($classname) || $classname;
}

# ------------------------------------------------------------------------------
# connect - Connect to a repository
# connect [options], $repo_dir
# options:
#   -force                        # Connect even when already connected
# ------------------------------------------------------------------------------

$USAGE{'connect'} = {
  summary => 'Connect to a template repository',
  params => Data::OrderedHash->new(
    '<repository>' => 'Can be any directory',
    '-force' => 'Connect even when already connected',
  ),
};

sub connect {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $opts = my_opts(\@_);
  my $repo_dir = shift or throw Error::MissingArg;
  throwf Error::Logical("Already connected to: '%s'\n",
    $self->{client}->{"$TMS_SETTINGS/repo_dir"})
      if $self->{repo} && !$opts->{force};
  $repo_dir = path_normalize($self->{client}->{'/'}->get_path . '/' . $repo_dir)
    unless path_is_absolute($repo_dir);
  throwf Error::Logical("Cannot connect to repository: %s\n", $repo_dir)
    unless $self->_ping_repository($repo_dir);
  $self->{client}->{$TMS_SETTINGS . '/' . 'repo_dir'} = $repo_dir;
  $self->{client}->{$TMS_SETTINGS}->save();
  $self->{client}->{$TMS_INSTANCE_DB} ||= {};
  $self->{client}->{$TMS_INSTANCE_DB}->save();
  # Connected
  $self->{repo} = Data::Hub->new($repo_dir);
  $self->print("Connected to: $repo_dir\n");
}

=pod

# XXX Not tested nor complete.
# XXX
# XXX Needs to be impl (~line 720) in the for loop
# XXX
# XXX Side effect stopped me from completing--all instances will be considered
# XXX out-of-date when global @use items are modified, even if the instance
# XXX doesn't really use it.

  $USAGE{'use'} = {
    summary => 'Add a spec to the global use line',
    params => Data::OrderedHash->new(
      '<spec>' => 'Spec',
    ),
  };

  sub use {
    my $self = shift;
    throw Error::NotStatic unless isa($self, __PACKAGE__);
    my $opts = my_opts(\@_);
    my $use = $self->{client}->{$TMS_SETTINGS . '/' . 'use'} ||= [];
    for (@_) {
      push_uniq @$use, split '\s*[;,]\s*';
    }
    $self->{client}->{$TMS_SETTINGS}->save();
  }

  $USAGE{'unuse'} = {
    summary => 'Remove a spec from the global use line',
    params => Data::OrderedHash->new(
      '<spec>' => 'Spec',
    ),
  };

  sub unuse {
    my $self = shift;
    throw Error::NotStatic unless isa($self, __PACKAGE__);
    my $opts = my_opts(\@_);
    my $use = $self->{client}->{$TMS_SETTINGS . '/' . 'use'} ||= [];
    return unless @$use;
    for (@_) {
      foreach my $spec (split '\s*[;,]\s*') {
        my $i = grep_first_index {$_ eq $spec} @$use;
        if (defined($i)) {
          splice @$use, $i, 1;
        }
      }
    }
    $self->{client}->{$TMS_SETTINGS}->save();
  }

=cut

# ------------------------------------------------------------------------------
# persist - Create a persistent connection to the repository
# persist $repo_dir
# ------------------------------------------------------------------------------

$USAGE{'persist'} = {
  summary => 'Create a persistent connection to the repository',
  params => Data::OrderedHash->new(
    '<repository>' => 'Can be any directory',
  ),
};

sub persist {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $opts = my_opts(\@_);
  my $repo_dir = shift or throw Error::MissingArg;
  # Update local connection
  my $current_repo_dir = $self->{client}->{"$TMS_SETTINGS/repo_dir"};
  if ($current_repo_dir ne $repo_dir) {
    $self->connect($current_repo_dir, -force);
  }
  # Update repository db
  my $client_dir = $self->{client}->{'/'}->get_path;
  my $repo = Data::Hub->new($repo_dir);
  $repo->{"$TMS_SETTINGS/clients"} ||= [];
  push_uniq $repo->{"$TMS_SETTINGS/clients"}, $client_dir;
  $repo->{"$TMS_SETTINGS"}->save;
}

# ------------------------------------------------------------------------------
# status - Print status for each instance
# status
# ------------------------------------------------------------------------------

$USAGE{'status'} = {
  summary => 'Status of targets',
  params => Data::OrderedHash->new(
    '[target]...' => 'Update specific targets',
  ),
  more =><<__end_more
status codes:
   \tOk, target is up-to-date
 M \tModified, target has been modified
 D \tDeleted, target is missing
 U \tUpdate needed, template (or dependency) is modified
 ! \tMissing, template is missing
__end_more
};

sub status {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->_validate_connection;
  my ($opts, @targets) = my_opts(\@_);
  foreach my $inst ($self->_get_instances(@targets)) {
    $inst->{status} = $self->_get_status($inst);
    next unless $inst->{status};
    $self->printf("%-6s %s\n", $inst->{status}, $inst->{target});
  }
}

# ------------------------------------------------------------------------------

$USAGE{'info'} = {
  summary => 'Print instance information for each target',
  params => Data::OrderedHash->new(
    '<target>...' => 'Target file or directory',
  ),
};

sub info {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->_validate_connection;
  my $opts = my_opts(\@_);
  my $parser = Parse::Template::Standard->new();
  my $out = str_ref;
  unless (@_) {
    my $props = {
      client_root => $self->{client}->get('/')->get_path,
      repo_root => $self->{client}->{"$TMS_SETTINGS/repo_dir"},
    };
    $parser->compile_text(\$TEXT_STATUS, $props, -out => $out);
#   my $instances = $self->{client}->{"/$TMS_INSTANCE_DB"} or return;
#   $instances->iterate(sub{
#     my ($key, $inst) = @_;
#     $inst->{status} = $self->_get_status($inst);
#   });
#   return;
  }
  foreach my $addr (@_) {
    my $inst = $self->_get_instance($addr)
      or throw Error::Simple "$addr is not a template instance\n";
    $inst->{status} = $self->_get_status($inst);
    $out = $parser->compile_text(\$TEXT_STATUS_ITEM, $inst, -out => $out);
  }
  $self->print($$out);
}
 
# ------------------------------------------------------------------------------
# update - Update the targets for all instances of modified templates
# update
# ------------------------------------------------------------------------------

$USAGE{'update'} = {
  summary => 'Update targets',
  params => Data::OrderedHash->new(
    '[target]...' => 'Update specific targets',
    '[<key>=<value>]...' => 'Data values, see also the -use option',
    '-use=<files>' => 'Comma-separated list of data files, file1,file2...',
    '-force' => 'Update even when target is up-to-date or modified',
    '-clear' => 'Clear any existing -use and key/value data',
  ),
};

sub update {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->_validate_connection;
  my ($opts, @targets) = my_opts(\@_);
  $self->_set_statuses;
  my @queue = ();
  if (@targets) {
    for (@targets) {
      last if /=/;
      my $key = $self->_addr_to_key($_);
      my $inst = $self->{client}->{"/$TMS_INSTANCE_DB/$key"};
      throw Error::Simple "$_ is not a template instance\n" unless $inst;
      push @queue, $inst;
    }
  } else {
    $self->{client}->{"/$TMS_INSTANCE_DB"}->iterate(sub{
      my ($checksum, $inst) = @_;
      push @queue, $inst;
    });
  }
  my %vars = map {(/([^=]+)=(.*)/)} @_;
  my @use = $opts->{use} ? split '\s*[;,]\s*', $opts->{use} : ();
  $opts->{force} = 1 if %vars or @use;
  foreach my $inst (@queue) {
    if (!$opts->{force} && $inst->{status} && $inst->{status} ne $STATUS_TEMPLATE_MODIFIED) {
      warn sprintf("Skipping (%s): %s\n", $inst->{status}, $inst->{target});
    }
    if (($inst->{status} && $inst->{status} eq $STATUS_TEMPLATE_MODIFIED) || $opts->{force}) {
      if ($$opts{clear}) {
        %{$inst->{vars}} = ();
        @{$inst->{use}} = ();
      }
      %vars and %{$inst->{vars}} = (%{$inst->{vars}}, %vars);
      @use and unshift_uniq($inst->{use}, @use);
      $self->_compile($inst);
    }
  }
}

# ------------------------------------------------------------------------------
# compile - Compile a template
# compile $template, @vars, [options]
# compile $template, $filename, @vars, [options]
#
# where:
#
#   @vars                     # Key/value pairs formatted as: key=value
#
# options:
#
#   -force => 1               # Generate even if target exists
#   -use => \@files           # Colon-separated list of data files
#
# If C<$filename> is omitted, output is written to STDOUT and the entry is not
# recorded in the instance database.
# ------------------------------------------------------------------------------

$USAGE{'compile'} = {
  summary => 'Compile a template',
  params => Data::OrderedHash->new(
    '<template>' => 'Relative to the <repository> you\'re connected to',
    '[target]' => 'Where to write the compiled result (otherwise STDOUT)',
    '[<key>=<value>]...' => 'Data values, see also the -use option',
    '-use=<files>' => 'Comma-separated list of data files, file1,file2...',
    '-force' => 'Compile even if target exists',
    '-export' => 'Do not create the instance entry for target',
  ),
};
 
sub compile {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->_validate_connection;
  my $opts = my_opts(\@_);
  my $addr = shift or throw Error::MissingArg;
  $addr = path_normalize("/$addr");
  my $query = $self->{repo}{$addr};
  throw Error::Simple "Template not found: $addr\n" unless $query;
  my @template_addrs = isa($query, 'Data::Hub::Subset')
    ? map {$self->{repo}->path_to_addr($_->get_path)} $query->values
    : ($addr);
  my $target_base = $_[0] && $_[0] =~ /=/ ? undef : shift;
  my %vars = map {(/([^=]+)=(.*)/)} @_;
  my @use = $opts->{use} ? split '\s*[;,]\s*', $opts->{use} : ();
  foreach my $template_addr (@template_addrs) {
    my $target_addr = $target_base;
    if ($target_addr) {
      if (isa($query, 'Data::Hub::Subset') || $target_addr eq '.') {
        $target_addr .= '/' . addr_name($template_addr);
      }
      $target_addr = addr_normalize($target_addr) or throw Error::Programatic;
      if ($self->{client}->{$target_addr} && !$opts->{force}) {
        warn sprintf("Target exists: %s\n", $target_addr) unless $opts->{quiet};
        next;
      }
    }
    my $inst = {
      'template' => $template_addr,
      'target' => $target_addr,
      'vars' => \%vars,
      'use' => \@use,
    };
    $self->_compile($inst, -no_db => $$opts{'export'} ? 1 : 0);
  }
}

# ------------------------------------------------------------------------------

$USAGE{'remove'} = {
  summary => 'Remove targets and their instance records',
  params => Data::OrderedHash->new(
    '<target>...' => 'Target file or directory',
    '-force' => 'Remove even when modified',
  ),
};

sub remove {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->_validate_connection;
  my $opts = my_opts(\@_);
  foreach my $addr (@_) {
    my $inst = $self->_get_instance($addr);
    unless ($inst) {
      warn "No such instance: $addr\n" unless $$opts{quiet};
      next;
    }
    my $status = $self->_get_status($inst);
    throw Error::Logical "Instance has modifications: $addr (use -force)\n"
      if $status && $status eq $STATUS_TARGET_MODIFIED && !$opts->{force};
    my $path = $self->{client}->addr_to_path($inst->{target});
    if (-d $path) {
      my $dir = $self->{client}->{$inst->{target}};
      foreach my $name ($dir->keys) {
        my $child_addr = $inst->{target} . '/' . $name;
        my $child_inst = $self->_get_instance($child_addr);
        next unless $child_inst;
        $self->remove($child_addr, -opts => $opts);
      }
      unless ($opts->{orphan}) {
        if ($dir->length == 0) {
          delete $self->{client}{$addr};
          $self->{client}{addr_parent($addr)}->save;
          $self->print('Removed: ', $path, "\n");
        }
      }
    } else {
      if ($self->{client}{$addr} && !$opts->{orphan}) {
        delete $self->{client}{$addr};
        my $addr_parent = addr_parent($addr) || '/';
        $self->{client}{$addr_parent}->save;
        $self->print('Removed: ', $path, "\n");
      }
    }
    my $key = $self->_addr_to_key($addr);
    delete $self->{client}{"$TMS_INSTANCE_DB/$key"};
  }
  $self->{client}{"$TMS_INSTANCE_DB"}->save;
}

# ------------------------------------------------------------------------------

$USAGE{'move'} = {
  summary => 'Move targets and their instance records',
  params => Data::OrderedHash->new(
    '<target>' => 'Target file or directory',
    '<new_target>' => 'New target file or directory',
    '-force' => 'Overwrite destination target if it exists',
  ),
};

sub move {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->_validate_connection;
  my $opts = my_opts(\@_);
  my $addr = addr_normalize(shift) or throw Error::MissingArg "<target>\n";
  my $new_addr = addr_normalize(shift) or throw Error::MissingArg "<new_target>\n";
  if ($self->_get_instance($new_addr) || $self->{client}->{"/$new_addr"}) {
    throw Error::Simple "Destination exists: $new_addr (use -force)"
      unless $opts->{force};
    $self->remove($new_addr, -force);
  }
  my $path = $self->{client}->addr_to_path($addr);
  my $new_path = $self->{client}->addr_to_path($new_addr);
  throw Error::Simple "Please remove '$new_addr' as it is in the way\n"
    if -e $new_path;
  if (-d $path) {
    dir_copy($path, $new_path);
    dir_remove($path);
  } else {
    file_copy($path, $new_path);
    file_remove($path);
  }
  $self->{client}->{"/$TMS_INSTANCE_DB"}->iterate(sub{
    my ($k, $v) = @_;
    my $old_target = $v->{target};
    if ($v->{target} eq $addr) {
      $v->{target} =~ s/^$addr/$new_addr/;
      delete $self->{client}->{"$TMS_INSTANCE_DB/$k"};
      my $new_k = $self->_addr_to_key($v->{target});
      $self->{client}->{"$TMS_INSTANCE_DB/$new_k"} = $v;
      $self->print("Moved: '$old_target' to '", $v->{target}, "'\n");
    }
  });
  $self->{client}->{$TMS_INSTANCE_DB}->save;
}

# ------------------------------------------------------------------------------

$USAGE{'orphan'} = {
  summary => 'Remove targets\' instance records',
  params => Data::OrderedHash->new(
    '<target>...' => 'Target file or directory',
  ),
};

sub orphan {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->remove(@_, '-force', '-orphan');
}

# ------------------------------------------------------------------------------

$USAGE{'diff'} = {
  summary => 'Difference between target and the latest compiled version',
  params => Data::OrderedHash->new(
    '[target]...' => 'Target file or directory',
    '-command=<command>' => 'Use this diff program, e.g., meld',
  ),
};

sub diff {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->_validate_connection;
  my $opts = my_opts(\@_, {command=>'diff'});
  my @instances = map {
    $self->_get_instance($_) or throw Error::Logical "No such instance: $_\n"
  } @_;
  unless (@instances) {
    my $entries = $self->{client}->{"/$TMS_INSTANCE_DB"};
    @instances = $entries->values;
  }
  foreach my $inst (@instances) {
    my $status = $self->_get_status($inst);
    next unless $status;
    my $fake = clone($inst, -keep_order);
    $fake->{target} = '.diff.' . $fake->{target};
    my $left = $self->{client}->addr_to_path($inst->{target});
    my $right = $self->{client}->addr_to_path($fake->{target});
    throw Error::Simple "Temp file exists: $right\n" if -e $right;
    $self->_compile($fake, -no_db, -quiet);
    my $target = $self->{client}->get($inst->{target});
    my $type = typeof($inst->{target}, $target);
    if ($type eq 'file-data-hash') {
      my $node = $self->{client}->get($fake->{target});
      my $diff = Data::Comparison::diff($target, $node);
      for (my $i = 0; $diff->[$i]; $i++) {
        my ($act, $addr, $rval) = @{$diff->[$i]};
        next if ($act eq '#'); # re-order
        if ($act eq '>') {
          my $lval = $target->get($addr);
          $self->printf("%s\n<   %s\n---\n>   %s\n", $addr, $rval, $lval);
        } else {
          $self->printf("%s   %s\n", $act, $addr);
        }
      }
    } else {
      # run diff
      system $opts->{command}, $left, $right;
    }
    file_remove($right);
  }
}

# ------------------------------------------------------------------------------

$USAGE{'list'} = {
  summary => 'List all instances and their corresponding templates',
  params => Data::OrderedHash->new(
  ),
};

sub list {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->_validate_connection;
  my ($opts, @targets) = my_opts(\@_);
  my $repo_dir = $self->{client}{"$TMS_SETTINGS/repo_dir"};
  my @out = ();
  foreach my $inst ($self->_get_instances(@targets)) {
    $inst->{status} = $self->_get_status($inst);
    push @out, [$inst->{status}, $inst->{target}, $inst->{template}];
  }
  my $w = 0;
  $w = max($w, length($_->[1])) for @out;
  $self->printf("%-6s %-${w}s %s\n", @$_) for @out;
}

# ------------------------------------------------------------------------------

$USAGE{'available'} = {
  summary => 'List available repository templates',
  params => Data::OrderedHash->new(
    '[path]' => 'Limit list to templates beneath this path',
  ),
};

sub available {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->_validate_connection;
  my $opts = my_opts(\@_);
  my $path = shift || '';
  $path =~ s/\/+$//;
  my $node = $self->{repo}->get($path . '/**');
  if ($node) {
    $self->print("$path/$_\n") for $node->keys;
  } else {
    throw Error::Simple "Path not found: $path";
  }
}

# ------------------------------------------------------------------------------
# _ping_repository - Test that the repository is reachable
# ------------------------------------------------------------------------------

sub _ping_repository {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $repo_dir = shift;
  -d $repo_dir;
}

# ------------------------------------------------------------------------------
# _validate_connection - Ensure the repository is valid
# _validate_connection
# ------------------------------------------------------------------------------

sub _validate_connection {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  throw Error::Logical "Not connected to a repository\n" unless $self->{repo};
  my $repo_dir = $self->{client}{"$TMS_SETTINGS/repo_dir"};
  $self->_ping_repository($repo_dir);
}

# ------------------------------------------------------------------------------
# _validate_persistent_connection - Ensure proper connection to the repository
# ------------------------------------------------------------------------------

sub _validate_persistent_connection {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  throw Error::Logical "Not connected to a repository\n" unless $self->{repo};
  my $clients = $self->{repo}->{"$TMS_SETTINGS/clients"};
  throwf Error::Logical("Not a valid repository: %s\n",
    $self->{repo}->{'/'}->get_path) unless $clients;
  my $cwd = $self->{client}->{'/'}->get_path;
  my $repo_dir = $self->{client}{"$TMS_SETTINGS/repo_dir"};
  $self->connect($repo_dir, '-force')
    unless grep_first {$_ eq $cwd} $clients->values;
}

# ------------------------------------------------------------------------------
# _get_instance - Return an entry from the instances db
# _get_instance $addr
# ------------------------------------------------------------------------------

sub _get_instance {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $key = $self->_addr_to_key(shift);
  $self->{client}->{"$TMS_INSTANCE_DB/$key"};
}

# ------------------------------------------------------------------------------
# _get_instances - Return an instance entry for each target address
# _get_instances @targets
# ------------------------------------------------------------------------------

sub _get_instances {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my @instances = map {
    $self->_get_instance($_) or throw Error::Logical "No such instance: $_\n"
  } @_;
  unless (@instances) {
    my $entries = $self->{client}->{"/$TMS_INSTANCE_DB"};
    @instances = $entries->values;
  }
  @instances;
}

# ------------------------------------------------------------------------------
# _addr_to_key - Return the instance db key for a given address
# _addr_to_key $addr
# ------------------------------------------------------------------------------

sub _addr_to_key {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $addr = shift or return;
  checksum(addr_normalize($addr));
}

# ------------------------------------------------------------------------------
# _compile - Compile according to the provided instance
# _compile $instance
#
# where:
#
#   $instance = {
#     template => $template_addr,
#     target => $target_addr || undef,
#     vars => \%vars,
#     use => \@paths,
#   }
#
# If C<$target_addr> is defined, the result will be written there.  Otherwise 
# the result will be printed to STDOUT.
# ------------------------------------------------------------------------------

sub _compile {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $opts = my_opts(\@_);
  my $inst = shift;
  my $target_path = $self->{client}->addr_to_path($inst->{target});
  my $target_key = $self->_addr_to_key($inst->{target});
  my $template_node = $self->{'repo'}->get($inst->{'template'});
  my $template_path = $template_node->get_path;
# my $template_path = $self->{repo}->addr_to_path($inst->{template});
  if (-d $template_path) {
    if ($target_key) {
      # Touch entry so that it exists before its children
      $self->{client}->{"$TMS_INSTANCE_DB/$target_key"} ||= {};
    }
    # Create directory
    if ($inst->{target}) {
      if (-e $inst->{target}) {
        throwf Error::Logical "Target exists and is not a directory: %s\n",
          $inst->{target} unless -d $inst->{target};
      } else {
        dir_create($inst->{target});
        my $rel_path =
          $self->{client}->path_relative($inst->{target}) || $inst->{target};
        $self->print('Wrote: ', $inst->{'target'}, "\n");
      }
    }
    # Process directory entries
    $self->{repo}->{$inst->{template}}->iterate(sub{
      my ($name, $child_node) = @_;
      my $child_addr = $inst->{template} . '/' . $name;
      my $child_inst = $self->_get_instance($child_addr);
      if ($child_inst) {
        $self->_compile($child_inst, -opts => $opts)
          if $self->_get_status($child_inst) eq $STATUS_TEMPLATE_MODIFIED;
      } else {
        # New child
        $child_inst = {%$inst};
        $child_inst->{template} .= '/' . $name;
        $child_inst->{target} and $child_inst->{target} .= '/' . $name;
        $self->_compile($child_inst, -opts => $opts);
      }
    });
  } elsif (!$template_node->isa(FS('TextFile'))) {
    file_copy($template_path, $target_path);
    throw Error::Simple "Copy error: $inst->{template}\n"
      unless -e $target_path;
    $self->print('Wrote: ', $inst->{'target'}, " (copy)\n");
  } else {
    # Compile template files
    $inst->{dep_checksums} = Data::OrderedHash->new();
    my @use = ();
    for (@{$inst->{use}}) {
      my $path = $_; # copy
      my ($loc, $node) = ();
      if ($path =~ s/^file:\///) {
        # abs path
        $loc = 'abs';
        $node = FS('Node')->new($path);
      } else {
        $loc = 'client';
        $node = $self->{client}{$path};
      }
      throw Error::Simple "Missing: $_\n" unless $node;
      push @use, $node;
      $inst->{dep_checksums}{"$loc:$path"} = _checksum($node);
#warnf "USE dependency: %s $_ -> $path\n", $inst->{dep_checksums}{"$loc:$path"};
    }
    my $repo_hist = {}; # Recognize dependancies by tracking file access
    my $client_hist = {}; # Recognize dependancies by tracking file access
    $self->{repo}->fs_access_log->add_listener($repo_hist);
    $self->{client}->fs_access_log->add_listener($client_hist);
    my $parser = Parse::Template::Standard->new($self->{repo});
    App::TMS::Debug::attach($parser);
    my $result = $parser->compile($inst->{template}, $inst->{vars}, @use, $self->{client});
    $self->{repo}->fs_access_log->remove_listener($repo_hist);
    $self->{client}->fs_access_log->remove_listener($client_hist);
    throw Error::Simple "Generation error: $inst->{template}\n"
      unless defined $result;
    chomp $$result; $$result .= "\n"; # ensure nl at eof
    # Add dependencies
    my $t_addr = $inst->{template};
    $inst->{dep_checksums}{"repo:$t_addr"} = _checksum($self->{repo}->get($t_addr));
    for (keys %$repo_hist) {
      my $addr = $self->{repo}->path_to_addr($_) || $_;
      next if $inst->{template} =~ /^$addr/;
      $inst->{dep_checksums}{"repo:$addr"} = _checksum($self->{repo}->get($addr));
    }
    for (keys %$client_hist) {
      my $addr = $self->{client}->path_to_addr($_) || $_;
      my $storage = $self->{client}->addr_to_storage($addr);
      $addr = $storage->get_addr();
      next if $addr eq '/'; # TODO Inspect fs_access code to see why, for this is bogus
                            # (while debugging config/daemon.opts)
#warnf "Template dependency: $_ -> $addr\n";
      $inst->{dep_checksums}{"client:$addr"} = _checksum($self->{client}->get($addr));
    }
    # Output result
    if ($inst->{target}) {
      $self->{client}->{$inst->{target}} = $result;
      $self->{client}->{$inst->{target}}->save;
      # TODO change file permissions according  to source
      $self->print('Wrote: ', $inst->{'target'}, "\n") unless $opts->{quiet};
      # Compute checksum
      my $target = $self->{client}->get($inst->{target});
      $inst->{checksum} = _checksum($target);
#warnf "CHECKSUM: %s (%s)\n", $inst->{checksum}, $target->get_addr;
    } else {
      $self->print($$result);
    }
  }
  # Create instance db entries
  if ($inst->{target} && ! $opts->{no_db}) {
    my $stat = stat($target_path);
    $inst->{'status'} = '';
    $self->{client}->{"$TMS_INSTANCE_DB/$target_key"} = $inst;
    $self->{client}->{"$TMS_INSTANCE_DB"}->save();
  }
};

# ------------------------------------------------------------------------------
# _set_statuses - Query and set status for each instance
# _set_statuses
# ------------------------------------------------------------------------------

sub _set_statuses {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $instances = $self->{client}->{"/$TMS_INSTANCE_DB"} or return;
  $instances->iterate(sub{
    my ($key, $inst) = @_;
    $inst->{status} = $self->_get_status($inst);
  });
  $self->{client}->{"/$TMS_INSTANCE_DB"}->save();
}

# ------------------------------------------------------------------------------
# _get_status - 
# ------------------------------------------------------------------------------

sub _get_status {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $inst = curry(shift) or throw Error::MissingArg;
  my $node = $self->{repo}{$inst->{template}} or return $STATUS_TEMPLATE_MISSING;
  my $template_path = $self->{'repo'}{$inst->{'template'}}->get_path;
  my $template_node = $self->{'repo'}->get($inst->{'template'});

  # Check target exists
  my $target = $self->{client}->get($inst->{target})
    or return $STATUS_TARGET_MISSING;
  my $type = typeof($inst->{target}, $target);
  # Check target
  if ($template_node->isa(FS('Directory'))) {
    # TODO Check for new/removed files, right?!
    return $STATUS_OK;
  } elsif (!$template_node->isa(FS('TextFile'))) {
    return $template_node->get_mtime > $target->get_mtime
      ? $STATUS_TARGET_MODIFIED
      : $STATUS_OK;
  } elsif (_checksum($target) != $inst->{checksum}) {
#warnf "CHECKSUM: %s (%s)\n", _checksum($target), $target->get_addr;
    return $STATUS_TARGET_MODIFIED;
  }
  # Check dependencies
  if ($inst->{dep_checksums}) {
    my $status = $STATUS_OK;
    foreach my $spec ($inst->{dep_checksums}->keys) {
      my $sum = $inst->{dep_checksums}{$spec};
#warnf "DEP CHECKSUM: %s (%s)\n", $sum, $spec;
      my ($ds, $addr) = $spec =~ /([a-z]+):(.*)/;
      my $dep_node = $ds eq 'abs'
        ? FS('Node')->new($addr)
        : $self->{$ds}->get($addr);
      if (!$dep_node) {
#warn "$spec is missing\n";
        $status = $STATUS_TEMPLATE_MISSING;
        last;
      }
      if ($sum != _checksum($dep_node)) {
#warn "$spec is modified: ", _checksum($dep_node), " != $sum\n";
        $status = $STATUS_TEMPLATE_MODIFIED;
        last;
      }
    }
    return $status;
  } else {
#warn "inst has no checksum data\n";
    return $STATUS_TEMPLATE_MODIFIED;
    }
}

sub _checksum {
  my $unk = shift;
  my $str = isa($unk, FS('Node')) ? $unk->get_raw_content : hf_format($unk);
  $str = isa($str, 'SCALAR') ? $$str : $str;
  my $sum = checksum $str;
#warnf "CHECKSUM: %s (%s)\n", $sum, $unk;
  $sum;
}

sub _save_instance_db {
  my $self = shift;
  $self->{client}->{$TMS_INSTANCE_DB}->save;
}

1;

__END__

=pod:summary Template Management System

=pod:synopsis

=pod:description

=cut
