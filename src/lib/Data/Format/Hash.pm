package Data::Format::Hash;
use strict;
our $VERSION = 2.1;

use Exporter qw(import);
use Perl::Module;
use Data::OrderedHash;
use Error::Programatic;
use Data::Hub::Address;
use Data::Hub::Util qw(addr_parent addr_pop);

our @EXPORT = qw();
our @EXPORT_OK = qw(
  HF_VERSION_MAJOR
  HF_VERSION_MINOR
  HF_VERSION_STR
  hf_parse
  hf_format
);
our %EXPORT_TAGS = (all => [@EXPORT_OK],);

# Format version
sub HF_VERSION_MAJOR  {2}
sub HF_VERSION_MINOR  {1}
sub HF_VERSION_STR    {HF_VERSION_MAJOR . '.' . HF_VERSION_MINOR}

# Constants
our $NEWLINE            = "\n";
our $SPACE              = ' ';
our $INDENT             = '  ';

# Literal constants
our $LIT_OPEN           = '{';
our $LIT_CLOSE          = '}';
our $LIT_HASH           = '%';
our $LIT_ARRAY          = '@';
our $LIT_SCALAR         = '$';
our $LIT_ASSIGN         = '=>';
our $LIT_COMMENT        = '#';
our $LIT_COMMENT_BEGIN  = '#{';
our $LIT_COMMENT_END    = '#}';

# Used in regular expressions
our $PAT_OPEN           = $LIT_OPEN;
our $PAT_CLOSE          = $LIT_CLOSE;
our $PAT_HASH           = $LIT_HASH;
our $PAT_ARRAY          = $LIT_ARRAY;
our $PAT_SCALAR         = "\\$LIT_SCALAR";
our $PAT_ASSIGN         = "(?<!\\\\)$LIT_ASSIGN";
our $PAT_ASSIGN_STRUCT  = '[\$\%\@]';
our $PAT_ASSIGN_BLOCK   = '<<';
our $PAT_COMMENT        = $LIT_COMMENT;
our $PAT_COMMENT_BEGIN  = $LIT_COMMENT_BEGIN;
our $PAT_COMMENT_END    = $LIT_COMMENT_END;
#our $PAT_LVAL           = '[\w\d\.\_\-\s]';
our $PAT_LVAL           = '[^\{\=]';
our $PAT_IRREGULAR_LVAL = '[\{\=]';
our $PAT_UNESCAPE       = '[\%\@\$\{\}\>\=\#]'; # backward compat
our $PAT_BLOCK_END      = '[a-zA-Z0-9_-]';

# Alias

sub hf_parse {goto &parse}
sub hf_format {goto &format}

# ------------------------------------------------------------------------------
# parse - Parse text into perl data structures
# parse \$text, [options]
# options:
#   -as_array=1         # Treat text as an array list (and return an array ref)
#   -hint=hint          # Usually a filename, used in debug/error output
# ------------------------------------------------------------------------------
#|test(!abort) use Data::Format::Hash qw(hf_parse);
#|test(match) # Parse a simple nested collection
#|my $d = q(
#|baz => biz
#|foo => %{
#|  bar => @{
#|    tender
#|    stool
#|  }
#|}
#|);
#|my $h = hf_parse(\$d);
#|$$h{'baz'};
#=biz
# ------------------------------------------------------------------------------

sub parse {
  my ($opts, $str) = my_opts(\@_, {
    'hint'      => undef,
    'as_array'  => 0,
  });
  my $text = isa($str, 'SCALAR') ? $str : \$str;
  my $root = $$opts{'into'} ? $$opts{'into'} : ();
  $root ||= $$opts{'as_array'} ? [] : Data::OrderedHash->new();
  my $ptr = $root;
  my $block_comment = 0;
  my $block_text = 0;
  my @parents = ();
  local $. = 0;

  for (split /\r?\n\r?/, $$text) {
    $.++;

    if ($block_comment) {
      # End of a block comment?
      /\s*$PAT_COMMENT_END/ and do {
        next if (ref($ptr) eq 'SCALAR');
        _trace($., "comment-e", $_);
        $block_comment = 0;
        next;
      };
      _trace($., "comment+", $_);
      next;
    }

    if ($block_text) {
      # End of a text block?
      /\s*$block_text\s*/ and do {
        _trace($., "txtblk-e", $_);
        $block_text = 0;
        $ptr = pop @parents;
        next;
      };
      _trace($., "txtblk+", $_);
      $$ptr .= $$ptr ? $NEWLINE . _unescape($_) : _unescape($_);
      next;
    }

    # Begin of a new hash structure
    /^\s*$PAT_HASH($PAT_LVAL*)\s*$PAT_OPEN\s*$/ and do {
      _trace($., "hash", $_);
      push @parents, $ptr;
      my $h = Data::OrderedHash->new();
      my $var_name = _trim_whitespace(\$1);
      isa($ptr, 'HASH') and $ptr->{$var_name} = $h;
      isa($ptr, 'ARRAY') and push @$ptr, $h;
      $ptr = $h;
      next;
    };

    # Begin of a new array structure
    /^\s*$PAT_ARRAY($PAT_LVAL*)\s*$PAT_OPEN\s*$/ and do {
      _trace($., "array", $_);
      push @parents, $ptr;
      my $a = [];
      my $var_name = _trim_whitespace(\$1);
      isa($ptr, 'HASH') and $ptr->{$var_name} = $a;
      isa($ptr, 'ARRAY') and push @$ptr, $a;
      $ptr = $a;
      next;
    };

    # Begin of a new scalar structure
    /^\s*$PAT_SCALAR($PAT_LVAL*)\s*$PAT_OPEN\s*$/ and do {
      _trace($., "scalar", $_);
      push @parents, $ptr;
      if (isa($ptr, 'HASH')) {
        my $var_name = _trim_whitespace(\$1);
        $ptr->{$var_name} = '';
        $ptr = \$ptr->{$var_name};
      } elsif (isa($ptr, 'ARRAY')) {
        push @$ptr, '';
        $ptr = \$ptr->[$#$ptr];
      }
      next;
    };

    # A block comment
    /^\s*$PAT_COMMENT_BEGIN/ and do {
      next if (ref($ptr) eq 'SCALAR');
      _trace($., "comment-b", $_);
      $block_comment = 1;
      next;
    };

    # A one-line comment
    /^\s*$PAT_COMMENT/ and do {
      if ($. == 1) {
        _trace($., "crown", $_);
        my @parts = split '\s';
        if (@parts >= 3 && $parts[0] =~ /^Hash(File|Format)$/) {
          my ($major, $minor) = split '\.', $parts[2];
          if ($major > HF_VERSION_MAJOR) {
            die "Hash format version '$major' is too new",
                _get_hint($., $_, $$opts{'hint'});
          }
        }
      } else {
        _trace($., "comment", $_);
      }
      next unless (ref($ptr) eq 'SCALAR');
    };

    # A one-line hash member value
    /^\s*($PAT_LVAL+)\s*$PAT_ASSIGN\s*(.*)/ and do {
      my $lval = $1;
      my $rval = $2;
      my $var_name = _trim_whitespace(\$lval);

      # Structure assignment
      $rval =~ /^($PAT_ASSIGN_STRUCT)\s*$PAT_OPEN\s*$/ and do {
        _trace($., "assign-$1", $_);
        unless (isa($ptr, 'HASH')) {
          warn "Cannot assign structure to '$ptr'",
              _get_hint($., $_, $$opts{'hint'});
          next;
        }
        push @parents, $ptr;
        if ($1 eq $LIT_HASH) {
          my $h = Data::OrderedHash->new();
          $ptr->{$var_name} = $h;
          $ptr = $h;
        } elsif ($1 eq $LIT_ARRAY) {
          my $a = [];
          $ptr->{$var_name} = $a;
          $ptr = $a;
        } elsif ($1 eq $LIT_SCALAR) {
          $ptr->{$var_name} = '';
          $ptr = \$ptr->{$var_name};
        } else {
          warn "Unexpected structure assignment",
              _get_hint($., $_, $$opts{'hint'});
        }
        next;
      };

      # Block assignment
      $rval =~ /$PAT_ASSIGN_BLOCK\s*($PAT_BLOCK_END+)\s*$/ and do {
        _trace($., "txtblk", $_);
        push @parents, $ptr;
        if (isa($ptr, 'HASH')) {
          $ptr->{$var_name} = '';
          $ptr = \$ptr->{$var_name};
        } elsif (isa($ptr, 'ARRAY')) {
          push @$ptr, '';
          $ptr = \$ptr->[$#$ptr];
        }
        $block_text = $1;
        next;
      };

      # Value assignment
      _trace($., "assign", $_);
      unless (isa($ptr, 'HASH')) {
        warn "Cannot assign variable to '$ptr'", _get_hint($., $_, $$opts{'hint'});
        isa($ptr, 'ARRAY') and push @$ptr, $_;
        isa($ptr, 'SCALAR') and $$ptr .= $_;
        next;
      }
      $ptr->{$var_name} = _unescape($rval);
      next;
    };

    # Close a structure
    /^\s*$PAT_CLOSE\s*$/ and do {
      _trace($., "close", $_);
      $ptr = pop @parents;
      unless (defined $ptr) {
        warn "No parent" . _get_hint($., $_, $$opts{'hint'});
      }
      next;
    };

    # A one-line array item
    ref($ptr) eq 'ARRAY' and do {
      _trace($., "array+", $_);
      s/^\s+//g;
      next if $_ eq ''; # Could be a blank line (arrays of hashes)
      push @$ptr, _unescape($_);
      next;
    };

    # Part of a scalar
    ref($ptr) eq 'SCALAR' and do {
      _trace($., "scalar+", $_);
      $$ptr .= $$ptr ? $NEWLINE . _unescape($_) : _unescape($_);
#     $$ptr .= $$ptr ? $NEWLINE . $_ : $_;
      next;
    };

    _trace($., "?", $_);
  }

  warn "Unclosed structure" . _get_hint($., 'EOF', $$opts{'hint'}) if @parents > 1;
  return $root;
}

# ------------------------------------------------------------------------------
# _trace - Debug output while parsing
# ------------------------------------------------------------------------------

sub _trace {
# warn sprintf("%4d: %10s %s\n", @_);
}

# ------------------------------------------------------------------------------
# _make_crown - Return the hash-format file crown
# ------------------------------------------------------------------------------

sub _make_crown {
  return '# HashFile ' . HF_VERSION_STR . "\n";
}

# ------------------------------------------------------------------------------
# format - Format nested data structure as string
# format [options]
#
# options:
#
#   -as_ref => 1        Return a reference (default 0)
#   -with_crown => 1    Prepend output with "# HashFile M.m" (where M.m is version)
# ------------------------------------------------------------------------------
#|test(!abort) use Data::Format::Hash qw(hf_format);
#|test(match) # Format a simple nested collection
#|my $d = {foo=>{bar=>['tender','stool']}};
#|hf_format($d)
#=foo => %{
#=  bar => @{
#=    tender
#=    stool
#=  }
#=}
# ------------------------------------------------------------------------------

sub format {
  my ($opts, $ref) = my_opts(\@_, {
    'as_ref' => 0, # Return a scalar reference instead of a scalar
    'with_crown' => 0, # Prepend the '# HashFile 2.1' firstline
    'indent_level' => 0, # Base indentation level
  });
  croak "Provide a reference" unless ref($ref);
  $opts->{'addr'} ||= new Data::Hub::Address();
  my $result = $$opts{'with_crown'} ? _make_crown() : '';
  _format($ref, undef, $$opts{'indent_level'}, undef, $opts, \$result);
  chomp $result;
  return $$opts{'as_ref'} ? \$result : $result;
}

# ------------------------------------------------------------------------------
# _format - Implementation of format
# ------------------------------------------------------------------------------

sub _format {
  my $ref = shift;
  my $name = shift;
  my $level = shift || 0;
  my $parent = shift;
  my $opts = shift;
  my $result = shift || str_ref();
  my $is_named = defined $name && $name ne ''; # 0 is a valid name

  # TODO handle undefined names (when other than level 0) otherwise the error
  # will happen on the parsing, i.e., a bad format is created.

  # Tame beastly names
  if ($is_named && $name =~ /$PAT_IRREGULAR_LVAL/) {
    $name =~ s/([^A-Za-z0-9_])/sprintf("_0x%2x_", unpack("C", $1))/eg;
    #TODO to unpack the name, add this to the `parse` function:
    #$str =~ s/_0x([a-fA-F0-9][a-fA-F0-9])_/pack("C",hex($1))/eg;
  }

  $is_named and $name =~ s/&#x([a-fA-F0-9]{2,3});/pack("C",hex($1))/eg;

  if ($opts->{ignore} && grep_first(sub {isa($ref, $_)}, @{$opts->{ignore}})) {

    $$result .= _get_indent($level) . $LIT_COMMENT.$SPACE;
    $$result .= $name.$SPACE.$LIT_ASSIGN.$SPACE if $is_named;
    $$result .= ref($ref).$NEWLINE;

  } elsif (isa($ref, 'HASH') || isa($ref, 'ARRAY')) {

    # Structure declaration and name
    if ($level > 0) {
      my $symbol = isa($ref, 'HASH') ? $LIT_HASH : $LIT_ARRAY;
#     if (defined $parent && isa($parent, 'HASH')) {
      if ($is_named) {
        $$result .= _get_indent($level) 
          .$name.$SPACE.$LIT_ASSIGN.$SPACE.$symbol.$LIT_OPEN.$NEWLINE;
      } else {
#       $$result .= _get_indent($level) .$symbol.$name.$LIT_OPEN.$NEWLINE;
        $$result .= _get_indent($level) .$symbol.$LIT_OPEN.$NEWLINE;
      }
    }

    # Contents
    if (isa($ref, 'HASH')) {
      $level++;
      for (keys %$ref) {
        $opts->{'addr'}->push($_);
        if (ref($$ref{$_})) {
          $$result .= ${_format($$ref{$_}, $_, $level, $ref, $opts)};
        } else {
          $$result .= ${_format(\$$ref{$_}, $_, $level, $ref, $opts)};
        }
        $opts->{'addr'}->pop();
      }
      $level--;
    } elsif (isa($ref, 'ARRAY')) {
      $level++;
      my $idx = 0;
      for (@$ref) {
        $opts->{'addr'}->push($idx++);
        $$result .= ref($_) ?
          ${_format($_, '', $level, $ref, $opts)} :
          ${_format(\$_, '', $level, $ref, $opts)};
        $opts->{'addr'}->pop();
      }
      $level--;
    }

    # Close the structure
    $$result .= _get_indent($level) . $LIT_CLOSE.$NEWLINE
      if $level > 0;

  } elsif (ref($ref) eq 'SCALAR') {

    my $value = $$ref;
    $value = '' unless defined $value;

    # Scalar
    if (index($value, "\n") > -1 || $value =~ /^\s+/
        || (defined $parent && isa($parent, 'ARRAY') && $value eq '')) {
      $$result .= _get_indent($level);
      if (defined $parent && isa($parent, 'HASH')) {
        $$result .= $name.$SPACE.$LIT_ASSIGN.$SPACE.$LIT_SCALAR.$LIT_OPEN.$NEWLINE;
      } else {
        $$result .= $LIT_SCALAR.$name.$LIT_OPEN.$NEWLINE;
      }
      # Write a scalar block to protect data
      $$result .= _escape($value).$NEWLINE;
      $$result .= _get_indent($level) .$LIT_CLOSE.$NEWLINE;
    } else {
      # One-line scalar (key/value)
      if ($is_named) {
        $$result .= _get_indent($level) .
        $name.$SPACE.$LIT_ASSIGN.$SPACE.$value.$NEWLINE;
      } else {
        $$result .= _get_indent($level)._escape($value).$NEWLINE;
      }
    }

  } elsif (isa($ref, 'JSON::XS::Boolean')) {
      $$result .= _get_indent($level) .
      $name.$SPACE.$LIT_ASSIGN.$SPACE.$ref.$NEWLINE;
  } else {
#   $ref = '' unless defined $ref;
    $$result .= _get_indent($level) . $LIT_COMMENT.$SPACE;
    $$result .= $name.$SPACE.$LIT_ASSIGN.$SPACE if $is_named;
    $$result .= $ref.'('.ref($ref).')'.$NEWLINE;
  }
  return $result;
}

sub _trim_whitespace {
  my $result = ${$_[0]};
  $result =~ s/^\s+|\s+$//g;
  return $result;
}

# ------------------------------------------------------------------------------
# _escape - Esacape patterns which would be interpred as control characters
# ------------------------------------------------------------------------------

sub _escape {
  my $result = $_[0];
  $result =~ s/(?<!\\)(=>|[\$\@\%]\{)/\\$1/g;
  $result =~ s/^(\s*)(?<!\\)\}/$1\\\}/gm;
  $result =~ s/^(\s*)(?<!\\)#/$1\\#/gm;
  return $result;
}#_escape

# ------------------------------------------------------------------------------
# _unescape - Remove protective backslashes
# ------------------------------------------------------------------------------

sub _unescape {
  my $result = $_[0];
# $result =~ s/\\($PAT_UNESCAPE)/$1/g;
  $result =~ s/\\(=>|[\$\@\%]\{)/$1/g;
  $result =~ s/^(\s*)\\\}/$1\}/gm;
  $result =~ s/^(\s*)\\#/$1#/gm;
  return $result;
}#_unescape

# ------------------------------------------------------------------------------
# _get_indent - Get the indent for formatting nested sructures
# _get_indent $level
# ------------------------------------------------------------------------------

sub _get_indent {
  my $indent = $INDENT;
  return $_[0] > 1 ? $indent x= ($_[0] - 1): '';
}

# ------------------------------------------------------------------------------
# _get_hint - Context information for error messages
# _get_hint $line_num, $line_text
# ------------------------------------------------------------------------------

sub _get_hint {
  my $result = '';
  if (defined $_[2]) {
    $result = " ($_[2])";
  }
  my $str =  substr($_[1], 0, 40);
  $str =~ s/^\s+//g;
  $result .= " at line $_[0]: '$str'";
  return $result;
}

1;

__END__

=pod:summary Parse and format perl data structures

=pod:synopsis

=pod:description

=cut
