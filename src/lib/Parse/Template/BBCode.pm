package Parse::Template::BBCode;
use strict;
our $VERSION = 0.1;
use base qw(Parse::Template::Base);

use Perl::Module;
use Data::Hub::Util qw(:all);
use Data::OrderedHash;
use Error::Programatic;

our %Default_Definitions = (
  b         => '<b>{2}</b>',
  i         => '<i>{2}</i>',
  u         => '<u>{2}</u>',
  img       => [
    '<img border="0" src="{2}"/>',
    '<img border="0" src="{2}" style="float:{1};"/>',
  ],
  url       => '<a href="{1}">{2}</a>',
  url2      => '<a target="_blank" href="{1}">{2}</a>',
  email     => '<a href="mailto:{1}">{2}</a>',
  color     => '<span style="color:{1};">{2}</span>',
  code      => '<code>{2}</code>',
  center    => '<p style="text-align: center;">{2}</p>',
  quote     => [
    '<blockquote>{2}</blockquote>',
    '{0}<blockquote>{2}</blockquote>',
  ],
  pre       => '<pre>{2}</pre>',
);

sub new {
  my $class = shift;
  my ($opts) = my_opts(\@_, {
    begin => '[',
    end => ']',
    close => '/',
    close_sep => '',
    directive => '',
  });
  my $self = $class->SUPER::new(-opts => $opts);
  @_ and push @{$$self{'root_stack'}}, @_;
  tie my %directives, 'Parse::Template::BBCode::Directives';
  $self->{directives} = \%directives;
  $self;
}

package Parse::Template::BBCode::Directives;
use strict;
our $VERSION = 0.1;
use Perl::Module;
use Tie::Hash;
use base qw(Tie::StdHash);
sub FETCH { [\&handler]; }
sub handler {
  my $self = shift;
  my $name = shift;
  my $bbcode_def = "/sys/conf/parser/bbcodes/\"$name\"";
  my $value = $self->get_value(\$bbcode_def) || $Default_Definitions{$name};
  $self->get_ctx->{collapse} = 0;
  return unless defined $value;
  my $attr = join(' ', @_) || '';
  my $block = '';
  my $text = $self->_slurp($name) or return;
  $self->_invoke(text => $text, out => \$block);
  my $vals = [$attr, ($attr || $block), $block];
  if (isa($value, 'ARRAY')) {
    $value = $attr && $block ? $value->[1] : $value->[0];
  }
  $value =~ s/\{([012])\}/$vals->[$1]/ge;
  $value;
}

1;

__END__
