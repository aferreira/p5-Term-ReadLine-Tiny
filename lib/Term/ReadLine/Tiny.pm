package Term::ReadLine::Tiny;
=head1 NAME

Term::ReadLine::Tiny - Tiny implementation of ReadLine

=head1 VERSION

version 1.03

=head1 SYNOPSIS

	use Term::ReadLine::Tiny;
	
	$term = Term::ReadLine::Tiny->new();
	while ( defined($_ = $term->readline("Prompt: ")) )
	{
		print "$_\n";
	}
	print "\n";
	
	$s = "";
	while ( defined($_ = $term->readkey(1)) )
	{
		$s .= $_;
	}
	print "\n$s\n";

=head1 DESCRIPTION

This package is a native perls implementation of ReadLine that doesn't need any library such as 'Gnu ReadLine'.
Also fully supports UTF-8, details in L<UTF-8 section|https://metacpan.org/pod/Term::ReadLine::Tiny#UTF-8>.

=head2 Keys

B<C<Enter> or C<^J> or C<^M>:> Gets input line. Returns the line unless C<EOF> or aborting or error, otherwise undef.

B<C<BackSpace> or C<^H> or C<^?>:> Deletes one character behind cursor.

B<C<Delete>:> Deletes one character at cursor. Does nothing if no character at cursor.

B<C<UpArrow>:> Changes line to previous history line.

B<C<DownArrow>:> Changes line to next history line.

B<C<RightArrow>:> Moves cursor forward to one character.

B<C<LeftArrow>:> Moves cursor back to one character.

B<C<Home>:> Moves cursor to the start of the line.

B<C<End>:> Moves cursor to the end of the line.

B<C<^D>:> Aborts the operation. Returns C<undef>.

=cut
use strict;
use warnings;
use v5.10.1;
use feature qw(switch);
no if ($] >= 5.018), 'warnings' => 'experimental';
require Term::ReadLine;
require Term::ReadKey;


BEGIN
{
	require Exporter;
	our $VERSION     = '1.03';
	our @ISA         = qw(Exporter);
	our @EXPORT      = qw();
	our @EXPORT_OK   = qw();
}


=head1 Standard Term::ReadLine Methods and Functions

=cut
=head2 ReadLine()

returns the actual package that executes the commands. If this package is used, the value is C<Term::ReadLine::Tiny>.

=cut
sub ReadLine
{
	return __PACKAGE__;
}

=head2 new([$appname[, IN[, OUT]]])

returns the handle for subsequent calls to following functions.
Argument I<appname> is the name of the application B<but not supported yet>.
Optionally can be followed by two arguments for IN and OUT filehandles. These arguments should be globs.

This routine may also get called via C<Term::ReadLine-E<gt>new()> if you have $ENV{PERL_RL} set to 'Tiny'.

=cut
sub new
{
	my $class = shift;
	my ($appname, $IN, $OUT) = @_;
	my $self = {};
	bless $self, $class;

	$self->newTTY($IN, $OUT);

	$self->{readmode} = '';
	$self->{history} = [];

	$self->{features} = {};
	#$self->{features}->{appname} = $appname;
	$self->{features}->{addhistory} = 1;
	$self->{features}->{minline} = 1;
	$self->{features}->{autohistory} = 1;
	$self->{features}->{changehistory} = 1;

	return $self;
}

sub DESTROY
{
	my $self = shift;
	if ($self->{readmode})
	{
		Term::ReadKey::ReadMode('restore', $self->{IN});
		$self->{readmode} = '';
	}
}

=head2 readline([$prompt[, $default]])

interactively gets an input line. Trailing newline is removed.

Returns C<undef> on C<EOF>.

=cut
sub readline
{
	my $self = shift;
	my ($prompt, $default) = @_;
	$prompt = "" unless defined($prompt);
	$default = "" unless defined($default);
	my ($in, $out, $history, $minline, $changehistory) = 
		($self->{IN}, $self->{OUT}, $self->{history}, $self->{features}->{minline}, $self->{features}->{changehistory});
	unless (-t $in)
	{
		my $line = <$in>;
		chomp $line if defined $line;
		return $line;
	}
	local $\ = undef;

	$self->{readmode} = 'cbreak';
	Term::ReadKey::ReadMode($self->{readmode}, $self->{IN});

	my @line;
	my ($line, $index) = ("", 0);
	my $history_index;
	my $ins_mode = 0;

	my $write = sub {
		my ($text, $ins) = @_;
		my $s;
		my @a = @line[$index..$#line];
		my $a = substr($line, $index);
		@line = @line[0..$index-1];
		$line = substr($line, 0, $index);
		print $out "\e[J";
		for my $c (split("", $text))
		{
			$s = encode_controlchar($c);
			unless ($ins)
			{
				print $out $s;
				push @line, $s;
				$line .= $c;
			} else
			{
				my $i = $index-length($line);
				$a[$i] = $s;
				substr($a, $i, 1) = $c;
			}
			$index++;
		}
		unless ($ins)
		{
			$s = join("", @a);
			print $out $s;
			print $out "\e[D" x length($s);
		} else
		{
			$s = join("", @a);
			print $out $s;
			print $out "\e[D" x (length($s) - length(join("", @a[0..length($text)-1])));
		}
		push @line, @a;
		$line .= $a;
	};
	my $print = sub {
		my ($text) = @_;
		$write->($text, $ins_mode);
	};
	my $set = sub {
		my ($text) = @_;
		print $out "\e[D" x length(join("", @line[0..$index-1]));
		print $out "\e[J";
		@line = ();
		$line = "";
		$index = 0;
		$write->($text);
	};
	my $backspace = sub {
		return if $index <= 0;
		my @a = @line[$index..$#line];
		my $a = substr($line, $index);
		$index--;
		print $out "\e[D" x length($line[$index]);
		@line = @line[0..$index-1];
		$line = substr($line, 0, $index);
		$write->($a);
		print $out "\e[D" x length(join("", @a));
		$index -= scalar(@a);
	};
	my $delete = sub {
		my @a = @line[$index+1..$#line];
		my $a = substr($line, $index+1);
		@line = @line[0..$index-1];
		$line = substr($line, 0, $index);
		$write->($a);
		print $out "\e[D" x length(join("", @a));
		$index -= scalar(@a);
	};
	my $home = sub {
		print $out "\e[D" x length(join("", @line[0..$index-1]));
		$index = 0;
	};
	my $end = sub {
		my @a = @line[$index..$#line];
		my $a = substr($line, $index);
		@line = @line[0..$index-1];
		$line = substr($line, 0, $index);
		$write->($a);
	};
	my $left = sub {
		return if $index <= 0;
		print $out "\e[D" x length($line[$index-1]);
		$index--;
	};
	my $right = sub {
		return if $index >= length($line);
		print $out $line[$index];
		$index++;
	};
	my $up = sub {
		return if $history_index <= 0;
		$history->[$history_index] = $line if $changehistory;
		$history_index--;
		$set->($history->[$history_index]);
	};
	my $down = sub {
		return if $history_index >= $#$history;
		$history->[$history_index] = $line if $changehistory;
		$history_index++;
		$set->($history->[$history_index]);
	};
	my $pageup = sub {
		return if $history_index <= 0;
		$history->[$history_index] = $line if $changehistory;
		$history_index = 0;
		$set->($history->[$history_index]);
	};
	my $pagedown = sub {
		return if $history_index >= $#$history;
		$history->[$history_index] = $line if $changehistory;
		$history_index = $#$history;
		$set->($history->[$history_index]);
	};

	print $prompt;
	$set->($default);
	push @$history, $line;
	$history_index = $#$history;

	my $result = undef;
	my ($char, $esc) = ("", undef);
	while (defined($char = getc($in)))
	{
		unless (defined($esc))
		{
			given ($char)
			{
				when (/\e/)
				{
					$esc = "";
				}
				when (/\x04/)
				{
					$result = undef;
					last;
				}
				when (/\n|\r/)
				{
					print $out $char;
					$history->[$#$history] = $line;
					pop @$history unless defined($minline) and length($line) >= $minline;
					$result = $line;
					last;
				}
				when (/[\b]|\x7F/)
				{
					$backspace->();
				}
				when (/[\x00-\x1F]|\x7F/)
				{
					$print->($char);
				}
				default
				{
					$print->($char);
				}
			}
			next;
		}
		$esc .= $char;
		if ($esc =~ /^.\d?\D/)
		{
			given ($esc)
			{
				when (/^\[(A|0A)/)
				{
					$up->();
				}
				when (/^\[(B|0B)/)
				{
					$down->();
				}
				when (/^\[(C|0C)/)
				{
					$right->();
				}
				when (/^\[(D|0D)/)
				{
					$left->();
				}
				when (/^\[(H|0H)/)
				{
					$home->();
				}
				when (/^\[(F|0F)/)
				{
					$end->();
				}
				when (/^\[(\d)~/)
				{
					given ($1)
					{
						when (1)
						{
							$home->();
						}
						when (2)
						{
							$ins_mode = not $ins_mode;
						}
						when (3)
						{
							$delete->();
						}
						when (4)
						{
							$end->();
						}
						when (5)
						{
							$pageup->();
						}
						when (6)
						{
							$pagedown->();
						}
						when (7)
						{
							$home->();
						}
						when (8)
						{
							$end->();
						}
						default
						{
							#$print->("\e$esc");
						}
					}
				}
				default
				{
					#$print->("\e$esc");
				}
			}
			$esc = undef;
		}
	}

	Term::ReadKey::ReadMode('restore', $self->{IN});
	$self->{readmode} = '';
	return $result;
}

=head2 addhistory($line1[, $line2[, ...]])

adds lines to the history of input.

=cut
sub addhistory
{
	my $self = shift;
	push @{$self->{history}}, @_;
	return (@_);
}

=head2 IN()

returns the filehandle for input.

=cut
sub IN
{
	my $self = shift;
	return $self->{IN};
}

=head2 OUT()

returns the filehandle for output.

=cut
sub OUT
{
	my $self = shift;
	return $self->{OUT};
}

=head2 MinLine([$minline])

If argument is specified, it is an advice on minimal size of line to be included into history.
C<undef> means do not include anything into history (autohistory off).

Returns the old value.

=cut
sub MinLine
{
	my $self = shift;
	my ($minline) = @_;
	my $result = $self->{features}->{minline};
	$self->{features}->{minline} = $minline if @_ >= 1;
	$self->{features}->{autohistory} = defined($self->{features}->{minline});
	return $result;
}

=head2 findConsole()

returns an array with two strings that give most appropriate names for files for input and output using conventions C<"<$in">, C<">out">.

=cut
sub findConsole
{
	return (Term::ReadLine::Stub::findConsole(@_));
}

=head2 Attribs()

returns a reference to a hash which describes internal configuration of the package. B<Not supported in this package.>

=cut
sub Attribs
{
	return {};
}

=head2 Features()

Returns a reference to a hash with keys being features present in current implementation.
This features are present:

=over

=item *

I<appname> is not present and is the name of the application. B<But not supported yet.>

=item *

I<addhistory> is present, always 1.

=item *

I<minline> is present, default 1. See C<MinLine> method.

=item *

I<autohistory> is present, C<FALSE> if minline is C<undef>. See C<MinLine> method.

=item *

I<changehistory> is present, default C<TRUE>. See C<changehistory> method.

=back

=cut
sub Features
{
	my $self = shift;
	my %features = %{$self->{features}};
	return \%features;
}

=head1 Additional Term::ReadLine Methods and Functions

=cut
=head2 newTTY([$IN[, $OUT]])

takes two arguments which are input filehandle and output filehandle. Switches to use these filehandles.

=cut
sub newTTY
{
	my $self = shift;
	my ($IN, $OUT) = @_;

	my ($console, $consoleOUT) = findConsole();
	my $in = $IN if ref($IN) eq "GLOB";
	$in = \$IN if ref(\$IN) eq "GLOB";
	open($in, '<', $console) unless defined($in);
	$in = \*STDIN unless defined($in);
	$self->{IN} = $in;
	my $out = $OUT if ref($OUT) eq "GLOB";
	$out = \$OUT if ref(\$OUT) eq "GLOB";
	open($out, '>', $consoleOUT) unless defined($out);
	$out = \*STDOUT unless defined($out);
	$self->{OUT} = $out;

	return ($self->{IN}, $self->{OUT});
}

=head1 Other Methods and Functions

=cut
=head2 readkey([$echo])

reads a key from input and echoes if I<echo> argument is C<TRUE>.

Returns C<undef> on C<EOF>.

=cut
sub readkey
{
	my $self = shift;
	my ($echo) = @_;
	my ($in, $out) = 
		($self->{IN}, $self->{OUT});
	unless (-t $in)
	{
		return getc($in);
	}
	local $\ = undef;

	$self->{readmode} = 'cbreak';
	Term::ReadKey::ReadMode($self->{readmode}, $self->{IN});

	my $result;
	my ($char, $esc) = ("", undef);
	while (defined($char = getc($in)))
	{
		unless (defined($esc))
		{
			given ($char)
			{
				when (/\e/)
				{
					$esc = "";
				}
				when (/\x04/)
				{
					$result = undef;
					last;
				}
				default
				{
					print $out encode_controlchar($char) if $echo;
					$result = $char;
					last;
				}
			}
			next;
		}
		$esc .= $char;
		if ($esc =~ /^.\d?\D/)
		{
			$result = "\e$esc";
			$esc = undef;
			last;
		}
	}

	Term::ReadKey::ReadMode('restore', $self->{IN});
	$self->{readmode} = '';
	return $result;
}

=head2 minline([$minline])

synonym of C<MinLine>.

=cut
sub minline
{
	return MinLine(@_);
}

=head2 changehistory([$changehistory])

If argument is specified, it allows to change history lines when argument value is true.

Returns the old value.

=cut
sub changehistory
{
	my $self = shift;
	my ($changehistory) = @_;
	my $result = $self->{features}->{changehistory};
	$self->{features}->{changehistory} = $changehistory if @_ >= 1;
	return $result;
}

=head2 history([$history])

If argument is specified and ArrayRef, rewrites all history by argument elements.

B<history([$line1[, $line2[, ...]]])>

If first argument is not ArrayRef, rewrites all history by argument values.

Returns copy of the old history in ArrayRef.

=cut
sub history
{
	my $self = shift;
	my @result = @{$self->{history}};
	if (@_ >= 1)
	{
		if (ref($_[0]) eq "ARRAY")
		{
			@{$self->{history}} = @{$_[0]};
		} else
		{
			@{$self->{history}} = @_;
		}
	}
	return \@result;
}

=head2 encode_controlchar($c)

encodes if argument C<c> is a control character, otherwise returns argument C<c>.

=cut
sub encode_controlchar
{
	my ($c) = @_;
	$c = substr($c, 0, 1);
	my $s;
	given ($c)
	{
		when (/[\x00-\x1F]/)
		{
			$s = "^".chr(0x40+ord($c));
		}
		when ($c =~ /[\x7F]/)
		{
			$s = "^".chr(0x3F);
		}
		default
		{
			$s = $c;
		}
	}
	return $s;
}


1;
__END__
=head1 UTF-8

C<Term::ReadLine::Tiny> fully supports UTF-8.

	$term = Term::ReadLine::Tiny->new();
	binmode($term->IN, ":utf8");
	binmode($term->OUT, ":utf8");
	while ( defined($_ = $term->readline("Prompt: ")) )
	{
		print "$_\n";
	}
	print "\n";

=head1 SEE ALSO

=over

=item *

L<Term::ReadLine::Tiny::readline|https://metacpan.org/pod/Term::ReadLine::Tiny::readline> - A non-OO package of Term::ReadLine::Tiny

=item *

L<Term::ReadLine|https://metacpan.org/pod/Term::ReadLine> - Perl interface to various readline packages

=back

=head1 INSTALLATION

To install this module type the following

	perl Makefile.PL
	make
	make test
	make install

from CPAN

	cpan -i Term::ReadLine::Tiny

=head1 DEPENDENCIES

This module requires these other modules and libraries:

=over

=item *

Term::ReadLine

=item *

Term::ReadKey

=back

=head1 REPOSITORY

B<GitHub> L<https://github.com/orkunkaraduman/p5-Term-ReadLine-Tiny>

B<CPAN> L<https://metacpan.org/release/Term-ReadLine-Tiny>

=head1 AUTHOR

Orkun Karaduman <orkunkaraduman@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2017  Orkun Karaduman <orkunkaraduman@gmail.com>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
