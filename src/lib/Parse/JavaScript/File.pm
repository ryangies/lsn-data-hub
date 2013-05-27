package Parse::JavaScript::File;
use strict;
use Perl::Module;
use Data::Hub::Util qw(:all);
use Parse::JavaScript::Tag;

# TODO
#
# * Emit deprication warnings when references are found. Deprecated items can
#   be indicated as:
#
#     @deprecated Thing (Use this instead)
#
# * When a static instance is provided by a package, it needs to provide its
#   class methods. Instances can be indicated as:
#
#     @instance foo <ecma.package.Class>
#
# * Use grammar to validate parent-child relationships
#
#     @structs = class,structure
#     @ends = member,function,constant,instance
#     @class = @ends,subclass
#
#     global
#     namespace = @structs,@ends
#     structure = @ends
#
# * Add the @obsolete tag for removed (previously deprecated) items

our @Scope = (
  [qw(global)],
  [qw(namespace)],
  [qw(class structure)],
  [qw(member function subclass constant instance deprecated)],
);

# Library-object members
our @Ignore = qw(
  id
  extend
  window
  document
);

sub Is_Context_Tag {
  my $tag_name = shift or return;
  $tag_name eq 'namespace';
}

sub Is_Class_Tag {
  my $tag_name = shift or return;
  $tag_name =~ /class$/;
}

sub new {
  my $classname = ref($_[0]) ? ref(shift) : shift;
  my $self = bless {
    'path' => undef,
    'provides' => [],
    'tags' => {},
    'usages' => [],
    'dependencies' => [],
  }, $classname;
  $self->parse(@_);
}

sub get_path { return $_[0]->{'path'}; }
sub get_provides { return @{$_[0]->{'provides'}}; }
sub get_tag { return $_[0]->{'tags'}{$_[1]}; }
sub get_usages { return @{$_[0]->{'usages'}}; }
sub get_dependencies { return @{$_[0]->{'dependencies'}}; }
sub add_dependency { return push @{$_[0]->{'dependencies'}}, $_[1]; }

sub unmarshal {
  my $self = shift;
  my $struct = shift;
  $self->{'path'} = $struct->{'path'};
  $self->{'provides'} = $struct->{'provides'};
  $self->{'usages'} = $struct->{'usages'};
  $self->{'dependencies'} = $struct->{'dependencies'};
  $self->{'tags'} = {};
  foreach my $id (keys %{$struct->{'tags'}}) {
    my $value = $struct->{'tags'}{$id};
    my $tag = new Parse::JavaScript::Tag();
    $tag->unmarshal($value);
    $self->{'tags'}{$id} = $tag;
  }
}

sub parse {
  my $self = shift or die;
  my $path = shift or return $self;
  $self->{'path'} = $path;
  my $content = file_read($self->{'path'});
  my $is_comment_block = 0;
  my $def = undef;
  my @prefix = ();
  my @tag_stack = ();
  for (split /[\r\n]+/, $$content) {
    s/\/\*// and $is_comment_block = 1;
    my $block_ends = s/\s*\*\///;
    if ($is_comment_block) {
      s/^[\s\/]*([\*=#L])?\s?//;
      my $em = $1;
      # TODO - Parse and store $tag_comment (for @deprecated hints)
      my ($tag_name, $tag_value, $tag_info) = /^@([a-z]+)\s*([\S]+)\s*(.*)/;
      if ($tag_name) {
        for (my $i = 0; $i < @Scope; $i++) {
          if (grep_first(sub {$_ eq $tag_name}, @{$Scope[$i]})) {
            my $tag = new Parse::JavaScript::Tag($tag_name, $tag_value, $tag_info);
            $tag_stack[$i] = $tag;
            $prefix[$i] = $tag_value;
            splice @tag_stack, $i+1;
            splice @prefix, $i+1;
            my @id = grep {defined && /\w/} @prefix;
            my $id = $tag->{'id'} = join('.', @id);
            next if $tag->is_context_tag;
            if (!$tag->is_class_tag) {
              my $parent_tag = $i > 0 ? $tag_stack[$i-1] : undef;
              next if $parent_tag && $parent_tag->is_class_tag;
            }
            push_uniq $self->{'provides'}, $id;
            $self->{'tags'}{$id} = $tag; # XXX no dup check
            last;
          }
        }
      }
    } else {
      s/\/\/.*//; # strip inline comments
      if (/\b(js|ecma)\.([a-zA-Z0-9_\$\.]+)/) {
        my $name = $2;
        $name =~ s/\.prototype\..*//;
        my @accessor = split /\./, $name;
        if (!grep {$accessor[0] eq $_} @Ignore) {
          pop @accessor if grep {$accessor[$#accessor] eq $_} qw(call apply);
          push_uniq $self->{'usages'}, join '.', @accessor
            unless @accessor <= 1;
        }
      }
    }
    if ($block_ends) {
      $is_comment_block = 0;
    };
  }
  $self;
}

1;
