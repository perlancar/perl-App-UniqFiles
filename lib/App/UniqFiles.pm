package App::UniqFiles;

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Cwd qw(abs_path);
use Exporter qw(import);
use Perinci::Sub::Util qw(gen_modified_sub);

# AUTHORITY
# DATE
# DIST
# VERSION

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

our %argspec_authoritative_dirs = (
    authoritative_dirs => {
        summary => 'Denote director(y|ies) where authoritative/"Original" copies are found',
        'x.name.is_plural' => 1,
        'x.name.singular' => 'authoritative_dir',
        schema => ['array*', of=>'str*'], # XXX dirname
        cmdline_aliases => {O=>{}},
    },
);
our %argspecs_filter = (
    include_file_patterns => {
        summary => 'Filename (including path) regex patterns to exclude',
        'x.name.is_plural' => 1,
        'x.name.singular' => 'include_file_pattern',
        schema => ['array*', of=>'str*'], # XXX re
        cmdline_aliases => {I=>{}},
    },
    exclude_file_patterns => {
        summary => 'Filename (including path) regex patterns to include',
        'x.name.is_plural' => 1,
        'x.name.singular' => 'exclude_file_pattern',
        schema => ['array*', of=>'str*'], # XXX re
        cmdline_aliases => {X=>{}},
    },
    exclude_empty_files => {
        schema => 'bool*',
        cmdline_aliases => {Z=>{}},
    },
    min_size => {
        summary => 'Minimum file size to consider',
        schema => 'filesize*',
    },
    max_size => {
        summary => 'Maximum file size to consider',
        schema => 'filesize*',
    },
);

$SPEC{uniq_files} = {
    v => 1.1,
    summary => 'Report duplicate or unique file contents',
    description => <<'_',

Given a list of filenames, will check each file size and content for duplicate
content. Interface is a bit like the `uniq` Unix command-line program.

_
    args    => {
        files => {
            schema => ['array*' => {of=>'str*'}],
            req    => 1,
            pos    => 0,
            slurpy => 1,
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
            schema => 'true*',
        },
        show_size => {
            summary => 'Show the size for each file',
            schema => 'true*',
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

Can be set to either 0, 1, 2, or 3.

If set to 0, duplicate items will not be returned.

If set to 1 (the default for `dupe-files`), will return all the the duplicate
files. For example: `file1` contains text 'a', `file2` 'b', `file3` 'a'. Then
`file1` and `file3` will be returned.

If set to 2 (the default for `uniq-files`), will only return the first of
duplicate items. Continuing from previous example, only `file1` will be returned
because `file2` is unique and `file3` contains 'a' (already represented by
`file1`). If one or more `--authoritative-dir` (`-O`) options are specified,
files under these directories will be preferred.

If set to 3, will return all but the first of duplicate items. Continuing from
previous example: `file3` will be returned. This is useful if you want to keep
only one copy of the duplicate content. You can use the output of this routine
to `mv` or `rm`. Similar to the previous case, if one or more
`--authoritative-dir` (`-O`) options are specified, then files under these
directories will not be listed if possible.

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

If set to 'name' then only name comparison will be performed. This of course can
potentially generate lots of false positives, but in some cases you might want
to compare filename for uniqueness.

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
        show_count => {
            schema => [bool => {default=>0}],
            summary => "Whether to return each file content's ".
                "number of occurence",
            description => <<'_',

1 means the file content is only encountered once (unique), 2 means there is one
duplicate, and so on.

_
            cmdline_aliases => {count=>{}, c=>{}},
        },
        detail => {
            summary => 'Show details (a.k.a. --show-digest, --show-size, --show-count)',
            schema => 'true*',
            cmdline_aliases => {l=>{}},
        },
        %argspec_authoritative_dirs,
        %argspecs_filter,
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
            summary   => 'List all files (recursively, and in detail) which have duplicate contents (all duplicate copies), exclude some files',
            src       => q(uniq-files -R -l -d -X '\.git/' --min-size 10k .),
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
    my $show_count       = $args{show_count}       // 0;
    my $show_digest      = $args{show_digest}      // 0;
    my $show_size        = $args{show_size}        // 0;
    my $digest_args      = $args{digest_args};
    my $algorithm        = $args{algorithm}        // ($digest_args ? 'Digest' : 'md5');
    my $group_by_digest  = $args{group_by_digest};

    if ($args{detail}) {
        $show_digest = 1;
        $show_size = 1;
        $show_count = 1;
    }

    my @authoritative_dirs = $args{authoritative_dirs} && @{$args{authoritative_dirs}} ?
        @{ $args{authoritative_dirs} } : ();
    for my $dir (@authoritative_dirs) {
        (-d $dir) or return [400, "Authoritative dir '$dir' does not exist or not a directory"];
        my $abs_dir = abs_path $dir or return [400, "Cannot get absolute path for authoritative dir '$dir'"];
        $dir = $abs_dir;
    }
    #log_trace "authoritative_dirs=%s", \@authoritative_dirs if @authoritative_dirs;

    my @include_re;
    for my $re0 (@{ $args{include_file_patterns} // [] }) {
        require Regexp::Util;
        my $re;
        if (ref $re0 eq 'Regexp') {
            $re = $re0;
        } else {
            eval { $re = Regexp::Util::deserialize_regexp("qr($re0)") };
            return [400, "Invalid/unsafe regex pattern in include_file_patterns '$re0': $@"] if $@;
            return [400, "Unsafe regex pattern (contains embedded code) in include_file_patterns '$re0'"] if Regexp::Util::regexp_seen_evals($re);
        }
        push @include_re, $re;
    }
    my @exclude_re;
    for my $re0 (@{ $args{exclude_file_patterns} // [] }) {
        require Regexp::Util;
        my $re;
        if (ref $re0 eq 'Regexp') {
            $re = $re0;
        } else {
            eval { $re = Regexp::Util::deserialize_regexp("qr($re0)") };
            return [400, "Invalid/unsafe regex pattern in exclude_file_patterns '$re0': $@"] if $@;
            return [400, "Unsafe regex pattern (contains embedded code) in exclude_file_patterns '$re0'"] if Regexp::Util::regexp_seen_evals($re);
        }
        push @exclude_re, $re;
    }

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

  FILTER: {
        my $ffiles;
      FILE:
        for my $f (@$files) {
            if (-l $f) {
                log_warn "File '$f' is a symlink, ignored";
                next FILE;
            }
            if (-d _) {
                log_warn "File '$f' is a directory, ignored";
                next FILE;
            }
            unless (-f _) {
                log_warn "File '$f' is not a regular file, ignored";
                next FILE;
            }

            if (@include_re) {
                my $included;
                for my $re (@include_re) {
                    if ($f =~ $re) { $included++; last }
                }
                unless ($included) {
                    log_info "File '$f' is not in --include-file-patterns, skipped";
                    next FILE;
                }
            }
            if (@exclude_re) {
                for my $re (@exclude_re) {
                    if ($f =~ $re) {
                        log_info "File '$f' is in --exclude-file-patterns, skipped";
                        next FILE;
                    }
                }
            }

            my $size = -s $f;
            if ($args{exclude_empty_files} && !$size) {
                log_info "File '$f' is empty, skipped by option -Z";
                next FILE;
            }
            if ($args{min_size} && $size < $args{min_size}) {
                log_info "File '$f' (size=$size) is smaller than min_file ($args{min_size}), skipped";
                next FILE;
            }
            if ($args{max_size} && $size > $args{max_size}) {
                log_info "File '$f' (size=$size) is larger than max_file ($args{max_size}), skipped";
                next FILE;
            }

            push @$ffiles, $f;
        }
        $files = $ffiles;
    } # FILTER

    my %name_files; # key = filename (computed), value = [path, ...]
  GROUP_FILE_NAMES: {
        for my $f (@$files) {
            #my $path = abs_path($f);
            (my $basename = $f) =~ s!.+/!!;
            $name_files{$basename} //= [];
            push @{ $name_files{$basename} }, $f
                unless grep { $_ eq $f } @{ $name_files{$basename} };
        }
        #use DD; dd \%name_files;
    }

    my %size_counts; # key = size, value = number of files having that size
    my %size_files; # key = size, value = [file, ...]
    my %file_sizes; # key = filename, value = file size, for caching stat()
  GET_FILE_SIZES: {
        for my $f (@$files) {
            my @st = stat $f;
            unless (@st) {
                log_error("Can't stat file `$f`: $!, skipped");
                next;
            }
            $size_counts{$st[7]}++;
            $size_files{$st[7]} //= [];
            push @{$size_files{$st[7]}}, $f;
            $file_sizes{$f} = $st[7];
        }
    }

    my $calc_digest = !($algorithm eq '' || $algorithm eq 'none' || $algorithm eq 'size' || $algorithm eq 'name');

    # calculate digest for all files having non-unique sizes
    my %digest_counts; # key = digest, value = num of files having that digest
    my %digest_files; # key = digest, value = [file, ...]
    my %file_digests; # key = filename, value = file digest
  CALC_FILE_DIGESTS: {
        last unless $calc_digest;
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
            $file_counts{$f} = $size_counts{ $file_sizes{$f} };
        } else {
            $file_counts{$f} = $digest_counts{ $file_digests{$f} };
        }
    }

  SORT_DUPLICATE_FILES: {
        last unless @authoritative_dirs;
        my $hash = $calc_digest ? \%digest_files : $algorithm eq 'name' ? \%name_files : \%size_files;
        for my $key (keys %$hash) {
            my @files = @{ $hash->{$key} };
            my @abs_files;
            next unless @files > 1;
            for my $file (@files) {
                my $abs_file = abs_path $file or do {
                    log_error "Cannot find absolute path for duplicate file '$file', skipping duplicate set %s", \@files;
                };
                push @abs_files, $abs_file;
            }

            #log_trace "Duplicate files before sorting: %s", \@files;
            @files = map { $files[$_] } sort {
                my $file_a = $abs_files[$a];
                my $file_a_in_authoritative_dirs = 0;
                my $subdir_len_file_a;
                for my $d (@authoritative_dirs) {
                    if ($file_a =~ m!\A\Q$d\E(?:/|\z)(.*)!) { $file_a_in_authoritative_dirs++; $subdir_len_file_a = length($1); last }
                }
                my $file_b = $abs_files[$b];
                my $file_b_in_authoritative_dirs = 0;
                my $subdir_len_file_b;
                for my $d (@authoritative_dirs) {
                    if ($file_b =~ m!\A\Q$d\E(?:/|\z)(.*)!) { $file_b_in_authoritative_dirs++; $subdir_len_file_b = length($1); last }
                }
                #log_trace "  file_a=<$file_a>, in authoritative_dirs? $file_a_in_authoritative_dirs";
                #log_trace "  file_b=<$file_b>, in authoritative_dirs? $file_b_in_authoritative_dirs";
                # files located near the root of authoritative dir is preferred
                # to deeper files. this is done by comparing subdir_len
                ($file_a_in_authoritative_dirs ? $subdir_len_file_a : 9999) <=> ($file_b_in_authoritative_dirs ? $subdir_len_file_b : 9999) ||
                    $file_a cmp $file_b;
            } 0..$#files;
            #log_trace "Duplicate files after sorting: %s", \@files;

            $hash->{$key} = \@files;
        }
    }

    #$log->trace("report_duplicate=$report_duplicate");
    my @files;
    for my $f (sort keys %file_counts) {
        if ($file_counts{$f} == 1) {
            #log_trace "unique file '$f'";
            push @files, $f if $report_unique;
        } else {
            #log_trace "duplicate file '$f'";
            my $is_first_copy = $calc_digest ?
                $f eq $digest_files{ $file_digests{$f} }[0] :
                $f eq $size_files{ $file_sizes{$f} }[0];
            #log_trace "is first copy? <$is_first_copy>";
            if ($report_duplicate == 0) {
                # do not report dupe files
            } elsif ($report_duplicate == 1) {
                push @files, $f;
            } elsif ($report_duplicate == 2) {
                push @files, $f if $is_first_copy;
            } elsif ($report_duplicate == 3) {
                push @files, $f unless $is_first_copy;
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
    my %resmeta;
    my $last_digest;
    for my $f (@files) {
        my $digest = $file_digests{$f} // $file_sizes{$f};

        # add separator row
        if ($group_by_digest && defined $last_digest && $digest ne $last_digest) {
            push @rows, ($show_count || $show_digest || $show_size) ? {} : '';
        }

        my $row;
        if ($show_count || $show_digest || $show_size) {
            $row = {file=>$f};
            $row->{count} = $file_counts{$f} if $show_count;
            $row->{digest} = $file_digests{$f} if $show_digest;
            $row->{size} = $file_sizes{$f} if $show_size;
        } else {
            $row = $f;
        }
        push @rows, $row;
        $last_digest = $digest;
    }

    $resmeta{'table.fields'} = [qw/file size digest count/];

    [200, "OK", \@rows, \%resmeta];
}

gen_modified_sub(
    base_name => 'uniq_files',
    output_name => 'dupe_files',
    description => <<'_',

This is a thin wrapper to <prog:uniq-files>. It defaults `report_unique` to 0
and `report_duplicate` to 1.

_
    modify_args => {
        report_unique => sub {
            $_[0]{schema} = [bool => {default=>0}];
        },
        report_duplicate => sub {
            $_[0]{schema} = [int => {in=>[0,1,2,3], default=>1}];
        },
    },
    modify_meta => sub {
        $_[0]{examples} = [
            {
                summary   => 'List all files (recursively, and in detail) which have duplicate contents (all duplicate copies)',
                src       => 'dupe-files -lR *',
                src_plang => 'bash',
                test      => 0,
                'x.doc.show_result' => 0,
            },
        ];
    },
    output_code => sub {
        my %args = @_;
        $args{report_unique} //= 0;
        $args{report_duplicate} //= 1;
        uniq_files(%args);
    },
);

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
