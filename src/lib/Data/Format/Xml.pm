package Data::Format::Xml;
use strict;
our $VERSION = 0.1;

use Exporter qw(import);
use Perl::Module;
use Error::Programatic;

our @EXPORT_OK = qw(xml_parse xml_format xml_strip);
our %EXPORT_TAGS = (all=>[@EXPORT_OK]);

# ==============================================================================

sub xml_parse {
  my $text = shift;
  my $p = Data::Format::Xml::Parser->new(@_);
  $p->compile_text(isa($text, 'SCALAR') ? $text : \$text);
}

# ------------------------------------------------------------------------------
# xml_format - Format the given data [Hash] as XML.
#
# my $xml_string = xml_format(\%data);
# my $xml_string = xml_format(\%data, -indent => '  '); # Use two-space indent
# my $xml_string = xml_format(\%data, -level => 1); # Initial indent level
# my $xml_string = xml_format(\%data, -end_tag_required => 1); # No inline tags
# ------------------------------------------------------------------------------

sub xml_format {
  my $h = shift;
  my $opts = my_opts(\@_, {
    indent => '',
    end_tag_required => 0,
    level => 0,
  });
  throw Error::IllegalArg unless isa($h, 'HASH');
  my $o = '';
  ($o .= _xml_format_node($opts, $_, $h->{$_})) for keys %$h;
  $o;
}

sub xml_strip {
  my $text = shift;
  my $p = Data::Format::Xml::Stripper->new(@_);
  $p->compile_text(isa($text, 'SCALAR') ? $text : \$text);
}

sub add_quotes {
  return unless defined $_[0];
  '"' . $_[0] . '"';
}

# ==============================================================================

sub _xml_format_node {
  my $opts = shift;
  my $k = shift;
  my $v = shift;
  my $o = '';
  if (isa($v, 'ARRAY')) {
    $o .= _xml_format_node($opts, $k, $_) for @$v;
  } elsif (isa($v, 'HASH')) {
    $o .= $opts->{indent} x $opts->{level};
    $o .= "<$k";
    my %skip = ();
    my $a = $v->{'.attrs'};
    if (isa($a, 'ARRAY')) {
      for (@$a) {
        $o .= ' ' . $_ . '=' . add_quotes($v->{$_});
        $skip{$_} = 1;
      }
    }
    my $content = '';
    if ($v->{'TextContent'}) {
      $content .= $v->{'TextContent'} =~ /[<>]/
        ? '<![CDATA[' . $v->{'TextContent'} . ']]>'
        : $v->{'TextContent'};
    } else {
      $opts->{indent} and $content .= "\n";
      $opts->{level}++;
      for (keys %$v) {
        next if $skip{$_} || $_ eq '.attrs';
        $content .= _xml_format_node($opts, $_, $v->{$_});
      }
      $opts->{level}--;
      $opts->{indent} and $content .= $opts->{indent} x $opts->{level};
    }
    $o .= $content && $content !~ /^\s+$/
      ? '>' . $content . "</$k>"
      : $k =~ /^\?/
        ? '?>'
        : $opts->{end_tag_required}
          ? "></$k>"
          : "/>";
    $opts->{indent} and $o .= "\n";
  } else {
    $o .= $opts->{indent} x $opts->{level};
    $o .= length($v) > 0
      ? "<$k>" . (isa($v, 'SCALAR') ? $$v : $v) . "</$k>"
      : $opts->{end_tag_required}
        ? "<$k></$k>"
        : "<$k/>";
    $opts->{indent} and $o .= "\n";
  }
  $o;
}

# ==============================================================================
# Reads XML and creates a nested hash.
# ==============================================================================

package Data::Format::Xml::Parser;
use strict;
our $VERSION = 0.1;
use base qw(Parse::Template::Base);

use Perl::Module;
use Data::Hub::Util qw(:all);
use Data::OrderedHash;
use Error::Programatic;

tie our %Directives, 'Data::Format::Xml::Directives';

# ------------------------------------------------------------------------------
# new - Initialize a parser appropriate for XML
# ------------------------------------------------------------------------------

sub new {
  my $class = shift;
  my ($opts) = my_opts(\@_, {
    begin => '<',
    end => '>',
    close => '/',
    close_sep => '',
    directive => '',
  });
  my $self = $class->SUPER::new(-opts => $opts);
  @_ and push @{$$self{'root_stack'}}, @_;
  $self->{directives} = \%Directives;
  my $hf = Data::Hub::Container->new(Data::OrderedHash->new);
  $self->{hf} = {
    root => $hf,
    ptr => $hf,
  };
  $self;
}

# ------------------------------------------------------------------------------
# compile_text - Return root hash object instead of output string
# ------------------------------------------------------------------------------

sub compile_text {
  my $self = shift;
  $self->SUPER::compile_text(@_);
  $self->{hf}{root};
}

1;

# ==============================================================================
# Tying the C<%Directives> hash to this package allows the "is this a 
# directive" lookup (in the base parser) to always use our XML tag handler.
# ==============================================================================

package Data::Format::Xml::Directives;
use strict;
our $VERSION = 0.1;

use Perl::Module;
use Tie::Hash;
use base qw(Tie::StdHash);
use Data::Format::Hash qw(:all);
use Data::OrderedHash;

sub remove_quotes {
  my $self = shift;
  return unless defined $_[0];
  $_[0] =~ s/^"//;
  $_[0] =~ s/"$//;
  if ($$self{'opts'}{'dequote'}) {
    $_[0] =~ s/^['"]//;
    $_[0] =~ s/['"]$//;
  }
  $_[0];
}

# ------------------------------------------------------------------------------
# FETCH - Return the handler which processes all tags
# ------------------------------------------------------------------------------

sub FETCH { [\&handler]; }

# ------------------------------------------------------------------------------
# handler - Process an XML tag
# ------------------------------------------------------------------------------

sub handler {
  my $self = shift;
  my $name = shift;
  tie my %children, qw(Data::Format::Xml::Node);
  if ($name =~ /^!/) {
    # Node is not data
    $self->_slurp('--') if ($name =~ /^!--/); # comments
    return ''; # output nothing
  }
  my $has_attrs = 0;
  if (@_) {
    # Node contains attributes
    $_[$#_] eq '/' and pop @_;
    $#_ >= 0 and $_[$#_] =~ s/[?\/]$//;
    {
      no warnings qw(misc); # 'Odd number of elements in hash assignment'
      %children = @_;
    }
    my @child_keys = keys %children;
    $children{'.attrs'} = [@child_keys];
    $children{$_} = remove_quotes($self, $children{$_}) for @child_keys;
    $has_attrs = 1;
  }
  # Split existing hash members into an array
  if ($self->{hf}{ptr}{$name}) {
    if (!isa($self->{hf}{ptr}{$name}, 'ARRAY')) {
      my $current = $self->{hf}{ptr}{$name};
      $self->{hf}{ptr}{$name} = [$current];
    }
  }
  # Read content
  my $contents = $name =~ s/\/$// ? str_ref('') : $self->_slurp($name);
  $contents ||= str_ref('');
  my $has_children = index($$contents, $self->{bs}) >= $[;
  # Assign content to structure
  if ($has_attrs || $has_children) {
    # Extract CDATA sections
    if ($$contents =~ s/^[\/\*\s]*<!\[CDATA\[[\/\*\s]*|[\/\*\s]*\]{2}>[\/\*\s]*$//g) {
      $children{'TextContent'} = $$contents;
      $has_children = 0;
    }
    # Advanced data node (contains attributes or content with nodes)
    if (isa($self->{hf}{ptr}{$name}, 'ARRAY')) {
      push @{$self->{hf}{ptr}{$name}}, \%children;
    } else {
      $self->{hf}{ptr}{$name} = \%children;
    }
    my $text_content = '';
    if ($has_children) {
      my $pptr = $self->{hf}{ptr};
      $self->{hf}{ptr} = \%children;
      $self->_invoke(text => $contents, out => \$text_content);
      $self->{hf}{ptr} = $pptr;
    } else {
      $text_content = $$contents;
    }
    $text_content =~ s/^\s+$//g;
    if ($text_content) {
      tied(%children)->set_content($text_content);
      $children{'TextContent'} = $text_content;
    }
  } else {
    # Simple data node (content only)
    if (isa($self->{hf}{ptr}{$name}, 'ARRAY')) {
      push @{$self->{hf}{ptr}{$name}}, $$contents;
    } else {
      $self->{hf}{ptr}{$name} = $$contents;
    }
  }
  ''; # output nothing
}

# ==============================================================================
# Special hash which returns its text content in scalar context
# ==============================================================================

package Data::Format::Xml::Node;
use strict;
our $VERSION = 0.1;

use Perl::Module;
use Tie::Hash;
use base qw(Tie::ExtraHash);
use Data::OrderedHash;

sub set_content {$_[0][1] = $_[1]}
sub TIEHASH {bless [Data::OrderedHash->new, ''], $_[0]}
sub SCALAR {$_[0][1]}

1;

# ==============================================================================
# Implentations for xml_strip
# ==============================================================================

package Data::Format::Xml::Stripper;
use strict;
use base qw(Data::Format::Xml::Parser);
tie our %Directives, 'Data::Format::Xml::Bambi';
sub new {
  my $self = shift->SUPER::new(@_);
  $self->{'directives'} = \%Directives;
  $self;
}
sub compile_text {
  my $self = shift;
  $self->SUPER::compile_text(@_);
  $self->get_ctx->{out};
}
1;

package Data::Format::Xml::Bambi;
use base qw(Tie::StdHash);
sub FETCH { [\&handler]; }
sub handler {''}
1;

__END__
