---
title: "Code & Links"
tags: [ruby, jekyll]
---

Inline `<img src="/logo.png">`, a [link](/about/), a [protocol-relative](//cdn.example.com/x.js) one and ![pic](/assets/pic.png).

```ruby
def hello
  puts "hi"
end
```

```ruby
puts "nolineno"
```
{: .nolineno }

```ruby
puts "file"
```
{: file="app/models/user.rb" }

```
<a href="/raw">plain block</a>
```

{% highlight ruby linenos %}
def tagged
  :linenos
end
{% endhighlight %}

{% highlight ruby %}
puts "tag without linenos"
{% endhighlight %}

A [scoped link]({{ "/scoped/" | relative_url }}).
