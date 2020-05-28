package App::UniqFiles;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(uniq_files);

our %SPEC;

sub _glob {
    require File::Find;

    my $dir;
    my @res;
    File::Find::finddepth(
        sub {
            return if -l $_;
            return unless -f _;
            no warnings 'once'; # $File::Find::dir
            push @res, "$File::Find::dir/$_";
        },
        @_,
    );
    @res;
}

$SPEC{uniq_files} = {
    v => 1.1,
    summary => 'Report or omit duplicate file contents',
    description => <<'_',

Given a list of filenames, will check each file size and content for duplicate
content. Interface is a bit like the `uniq` Unix command-line program.

_
    args    => {
        files => {
            schema => ['array*' => {of=>'str*'}],
            req    => 1,
            pos    => 0,
            greedy => 1,
        },
        recurse => {
            schema => 'bool*',
            cmdline_aliases => {R=>{}},
            description => <<'_',

If set to true, will recurse into subdirectories.

_
        },
        group_by_digest => {
            summary => 'Sort files by its digest (or size, if not computing digest), separate each different digest',
            schema => 'bool*',
        },
        show_digest => {
            summary => 'Show the digest value (or the size, if not computing digest) for each file',
            description => <<'_',

Note that this routine does not compute digest for files which have unique
sizes, so they will show up as empty.

_
            schema => 'bool*',
        },
        # TODO add option follow_symlinks?
        report_unique => {
            schema => [bool => {default=>1}],
            summary => 'Whether to return unique items',
            cmdline_aliases => {
                a => {
                    summary => 'Alias for --report-unique --report-duplicate=1 (report all files)',
                    code => sub {
                        my $args = shift;
                        $args->{report_unique}    = 1;
                        $args->{report_duplicate} = 1;
                    },
                },
                u => {
                    summary => 'Alias for --report-unique --report-duplicate=0',
                    code => sub {
                        my $args = shift;
                        $args->{report_unique}    = 1;
                        $args->{report_duplicate} = 0;
                    },
                },
                d => {
                    summary =>
                        'Alias for --noreport-unique --report-duplicate=1',
                    code => sub {
                        my $args = shift;
                        $args->{report_unique}    = 0;
                        $args->{report_duplicate} = 1;
                    },
                },
                D => {
                    summary =>
                        'Alias for --noreport-unique --report-duplicate=3',
                    code => sub {
                        my $args = shift;
                        $args->{report_unique}    = 0;
                        $args->{report_duplicate} = 3;
                    },
                },
            },
        },
        report_duplicate => {
            schema => [int => {in=>[0,1,2,3], default=>2}],
            summary => 'Whether to return duplicate items',
            description => <<'_',

Can be set to either 0, 1, 2.

If set to 2 (the default), will only return the first of duplicate items. For
example: `file1` contains text 'a', `file2` 'b', `file3` 'a'. Only `file1` will
be returned because `file2` is unique and `file3` contains 'a' (already
represented by `file1`).

If set to 1, will return all the the duplicate files. From the above example:
`file1` and `file3` will be returned.

If set to 3, will return all but the first of duplicate items. From the above
example: `file3` will be returned. This is useful if you want to keep only one
copy of the duplicate content. You can use the output of this routine to `mv` or
`rm`.

If set to 0, duplicate items will not be returned.

_
            cmdline_aliases => {
            },
        },
        algorithm => {
            schema => ['str*'],
            summary => "What algorithm is used to compute the digest of the content",
            description => <<'_',

The default is to use `md5`. Some algorithms supported include `crc32`, `sha1`,
`sha256`, as well as `Digest` to use Perl <pm:Digest> which supports a lot of
other algorithms, e.g. `SHA-1`, `BLAKE2b`.

If set to '', 'none', or 'size', then digest will be set to file size. This
means uniqueness will be determined solely from file size. This can be quicker
but will generate a false positive when two files of the same size are deemed as
duplicate even though their content may be different.

_
        },
        digest_args => {
            schema => ['array*',

                       # comment out temporarily, Perinci::Sub::GetArgs::Argv
                       # clashes with coerce rules; we should fix
                       # Perinci::Sub::GetArgs::Argv to observe coercion rules
                       # first
                       #of=>'str*',

                       'x.perl.coerce_rules'=>['From_str::comma_sep']],
            description => <<'_',

Some Digest algorithms require arguments, you can pass them here.

_
            cmdline_aliases => {A=>{}},
        },
        count => {
            schema => [bool => {default=>0}],
            summary => "Whether to return each file content's ".
                "number of occurence",
            description => <<'_',

1 means the file content is only encountered once (unique), 2 means there is one
duplicate, and so on.

_
            cmdline_aliases => {c=>{}},
        },
    },
    examples => [
        {
            summary   => 'List all files which do no have duplicate contents',
            src       => 'uniq-files *',
            src_plang => 'bash',
            test      => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary   => 'List all files which have duplicate contents',
            src       => 'uniq-files -d *',
            src_plang => 'bash',
            test      => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary   => 'Move all duplicate files (except one copy) in this directory (and subdirectories) to .dupes/',
            src       => 'uniq-files -D -R * | while read f; do mv "$f" .dupes/; done',
            src_plang => 'bash',
            test      => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary   => 'List number of occurences of contents for duplicate files',
            src       => 'uniq-files -c *',
            src_plang => 'bash',
            test      => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary   => 'List number of occurences of contents for all files',
            src       => 'uniq-files -a -c *',
            src_plang => 'bash',
            test      => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary   => 'List all files, along with their number of content occurrences and content digest. '.
                'Use the BLAKE2b digest algorithm. And group the files according to their digest.',
            src       => 'uniq-files -a -c --show-digest -A BLAKE2,blake2b *',
            src_plang => 'bash',
            test      => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub uniq_files {
    my %args = @_;

    my $files = $args{files};
    return [400, "Please specify files"] if !$files || !@$files;
    my $recurse          = $args{recurse};
    my $report_unique    = $args{report_unique}    // 1;
    my $report_duplicate = $args{report_duplicate} // 2;
    my $count            = $args{count}            // 0;
    my $show_digest      = $args{show_digest}      // 0;
    my $digest_args      = $args{digest_args};
    my $algorithm        = $args{algorithm}        // ($digest_args ? 'Digest' : 'md5');
    my $group_by_digest  = $args{group_by_digest};

    if ($recurse) {
        $files = [ map {
            if (-l $_) {
                ();
            } elsif (-d _) {
                (_glob($_));
            } else {
                ($_);
            }
        } @$files ];
    }

    # filter non-regular files
    my $ffiles;
    for my $f (@$files) {
        if (-l $f) {
            log_warn "File '$f' is a symlink, ignored";
            next;
        }
        if (-d _) {
            log_warn "File '$f' is a directory, ignored";
            next;
        }
        unless (-f _) {
            log_warn "File '$f' is not a regular file, ignored";
            next;
        }
        push @$ffiles, $f;
    }
    $files = $ffiles;

    my %size_counts; # key = size, value = number of files having that size
    my %file_sizes; # key = filename, value = file size, for caching stat()
  GET_FILE_SIZES: {
        for my $f (@$files) {
            my @st = stat $f;
            unless (@st) {
                log_error("Can't stat file `$f`: $!, skipped");
                next;
            }
            $size_counts{$st[7]}++;
            $file_sizes{$f} = $st[7];
        }
    }

    # calculate digest for all files having non-unique sizes
    my %digest_counts; # key = digest, value = num of files having that digest
    my %digest_files; # key = digest, value = [file, ...]
    my %file_digests; # key = filename, value = file digest
  CALC_FILE_DIGESTS: {
        last if $algorithm eq '' || $algorithm eq 'none' || $algorithm eq 'size';
        require File::Digest;

        for my $f (@$files) {
            next unless defined $file_sizes{$f}; # just checking. all files should have sizes.
            next if $size_counts{ $file_sizes{$f} } == 1; # skip unique file sizes.
            my $res = File::Digest::digest_file(
                file=>$f, algorithm=>$algorithm, digest_args=>$digest_args);
            return [500, "Can't calculate digest for file '$f': $res->[0] - $res->[1]"]
                unless $res->[0] == 200;
            my $digest = $res->[2];
            $digest_counts{$digest}++;
            $digest_files{$digest} //= [];
            push @{$digest_files{$digest}}, $f;
            $file_digests{$f} = $digest;
        }
    }

    my %file_counts; # key = file name, value = num of files having file content
    for my $f (@$files) {
        next unless defined $file_sizes{$f}; # just checking
        if (!defined($file_digests{$f})) {
            $file_counts{$f} = 1;
        } else {
            $file_counts{$f} = $digest_counts{ $file_digests{$f} };
        }
    }

    #$log->trace("report_duplicate=$report_duplicate");
    my @files;
    for (sort keys %file_counts) {
        if ($file_counts{$_} == 1) {
            #$log->trace("unique file `$_`");
            push @files, $_ if $report_unique;
        } else {
            #$log->trace("duplicate file `$_`");
            if ($report_duplicate == 0) {
                # do not report dupe files
            } elsif ($report_duplicate == 1) {
                push @files, $_;
            } elsif ($report_duplicate == 2) {
                my $digest = $file_digests{$_};
                push @files, $_ if $_ eq $digest_files{$digest}[0];
            } elsif ($report_duplicate == 3) {
                my $digest = $file_digests{$_};
                push @files, $_ if $_ ne $digest_files{$digest}[0];
            } else {
                die "Invalid value for --report-duplicate ".
                    "'$report_duplicate', please choose 0/1/2/3";
            }
        }
    }

  GROUP_FILES_BY_DIGEST: {
        last unless $group_by_digest;
        @files = sort {
            $file_sizes{$a} <=> $file_sizes{$b} ||
            ($file_digests{$a} // '') cmp ($file_digests{$b} // '')
        } @files;
    }

    my @rows;
    my $last_digest;
    for my $f (@files) {
        my $digest = $file_digests{$f} // $file_sizes{$f};

        # add separator row
        if ($group_by_digest && defined $last_digest && $digest ne $last_digest) {
            push @rows, ($count || $show_digest) ? [] : '';
        }

        my $row;
        if ($count || $show_digest) {
            $row = [$f];
            push @$row, $file_counts{$f} if $count;
            push @$row, $file_digests{$f} if $show_digest;
        } else {
            $row = $f;
        }
        push @rows, $row;
        $last_digest = $digest;
    }
    [200, "OK", \@rows];
}

1;
#ABSTRACT:

=head1 SYNOPSIS

 # See uniq-files script


=head1 NOTES


=head1 SEE ALSO

L<find-duplicate-filenames> from L<App::FindUtils>

L<move-duplicate-files-to> from L<App::DuplicateFilesUtils>, which is basically
a shortcut for C<< uniq-files -D -R . | while read f; do mv "$f" SOMEDIR/; done
>>.
