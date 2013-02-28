Generate layouts

    rake parse_haml

Generate css

    cd _scss
    compass compile

Generate pygments css

    pygmentize -a .highlight -S default -f html > css/pygments.css
    pygmentize -a .highlight -S monokai -f html > css/monokai.css

Building posts

    jekyll

Running a local server

    jekyll --server --auto

Uploading to S3

    s3cmd sync _site/ s3://www.jonb.org/ --acl-public --guess-mime-type