/// The reply the streaming demo replays.
///
/// Deliberately exhaustive: every construct the package renders appears here,
/// and the awkward combinations appear too — a table cell holding maths with a
/// `|` in it, an equation opened on a list marker, emphasis nested three deep,
/// a fence inside a list item, a quote inside a quote.
///
/// A reveal only looks smooth on the easy half of a document. The point of
/// this one is to make the hard half visible: constructs that restyle when
/// their closing delimiter lands, blocks with no half-state to reveal, and
/// anything whose width changes as it arrives.
library;

/// A reply exercising every supported construct — including the CommonMark
/// additions: underscore emphasis, multi-backtick code, tilde and nested
/// fences, setext headings, escapes, entities, a hidden comment, `$$` maths,
/// link titles, reference links, citation URLs and footnotes. The
/// definitions at the end stream in last, so the links, chips and footnote
/// numbers above them appear once their definitions arrive.
const String streamingReply = r'''# Reversing a linked list

Here is the **iterative** approach. It runs in \( O(n) \) time and uses
\( O(1) \) extra space, which is why it is *usually* preferred over
recursion — and it is ***far*** easier to reason about under a debugger.

## The idea

Walk the list once and, as you go, point each node back at the one before
it. You need three references at any moment:

1. `prev` — the part already reversed
2. `curr` — the node being moved
3. `next` — saved before you overwrite `curr.next`

### Emphasis, every way round

Plain, **bold**, *italic*, ***bold italic***, ~~struck through~~,
<u>underlined</u>, `inline code`, and *italic wrapping **bold** and back to
italic*. Escapes hold too: \*not italic\* and a literal \| pipe.

Underscores work the same way — __bold__, _italic_, ___both___ — but never
inside a word, so `snake_case` and snake_case_name stay plain. Double
backticks hold a backtick: `` call `reverse` here ``. Entities decode:
&copy; &mdash; &rarr; &le; &#x1F680;, and 2 * 3 * 4 is arithmetic.

Setext heading, underlined
--------------------------

<!-- A comment the reader never sees, even mid-stream. -->

## The code

```dart
ListNode? reverse(ListNode? head) {
  ListNode? prev;
  var curr = head;
  while (curr != null) {
    final next = curr.next;   // save it before overwriting
    curr.next = prev;
    prev = curr;
    curr = next;
  }
  return prev;
}
```

The same in Python, in a tilde fence:

~~~python
def reverse(head):
    prev = None
    while head:
        head.next, prev, head = prev, head, head.next
    return prev
~~~

A longer fence can show a fence inside it:

````markdown
```dart
reverse(head);
```
````

A fence with no language, holding characters that look like markup:

```
**not bold**  `not code`  | not | a | table |
```

## Complexity

| Approach  | Time | Space | Modulus \(|z|\) | Notes                    |
|-----------|:----:|:-----:|:---------------:|--------------------------|
| Iterative | O(n) | O(1)  | \(\sqrt{5}\)    | preferred                |
| Recursive | O(n) | O(n)  | `a|b`           | stack depth is the list  |
| Hybrid    | O(n) | O(1)  | 1               | ***rarely*** worth it    |

## The maths

In dollars, too — a price like $5 stays text, and a block opens with `$$`:

$$
S(n) = \sum_{k=0}^{n-1} 1 = n
$$

The cost of the recursive form is the sum of the frames it opens:

\[
T(n) = \sum_{k=1}^{n} 1 = n \quad\Rightarrow\quad O(n)
\]

1. \[
\frac{7x^3}{x^2} = 7x \to +\infty
\]
2. Which is why the iterative form wins on space.

## Longer derivations

Completing the square turns \( ax^2 + bx + c = 0 \) into the quadratic
formula, one aligned step at a time:

\[
\begin{aligned}
ax^2 + bx + c &= 0 \\
x^2 + \frac{b}{a}x &= -\frac{c}{a} \\
\left(x + \frac{b}{2a}\right)^2 &= \frac{b^2 - 4ac}{4a^2} \\
x &= \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
\end{aligned}
\]

The Gaussian integral, squared and moved to polar coordinates:

\[
\begin{aligned}
I^2 &= \int_{-\infty}^{\infty}\!\int_{-\infty}^{\infty} e^{-(x^2+y^2)}\,dx\,dy \\
&= \int_{0}^{2\pi}\!\int_{0}^{\infty} e^{-r^2}\,r\,dr\,d\theta \\
&= 2\pi\left[-\tfrac{1}{2}e^{-r^2}\right]_{0}^{\infty} = \pi
\quad\Rightarrow\quad I = \sqrt{\pi}
\end{aligned}
\]

Maxwell's equations, with a numbered line for each:

\[
\begin{align}
\nabla \cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0} \\
\nabla \cdot \mathbf{B} &= 0 \\
\nabla \times \mathbf{E} &= -\frac{\partial \mathbf{B}}{\partial t} \\
\nabla \times \mathbf{B} &= \mu_0 \mathbf{J}
  + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t}
\end{align}
\]

A piecewise function next to a matrix and its determinant:

\[
f(x) = \begin{cases}
x^2 \sin \frac{1}{x} & x \neq 0 \\
0 & x = 0
\end{cases}
\qquad
A = \begin{pmatrix} 1 & 2 & 3 \\ 0 & 1 & 4 \\ 5 & 6 & 0 \end{pmatrix},
\quad \det A = 1
\]

Two Taylor series, long enough to need the full width:

\[
e^{x} = \sum_{n=0}^{\infty} \frac{x^n}{n!}
= 1 + x + \frac{x^2}{2!} + \frac{x^3}{3!} + \frac{x^4}{4!} + \cdots,
\qquad
\sin x = \sum_{n=0}^{\infty} \frac{(-1)^n\, x^{2n+1}}{(2n+1)!}
\]

And some chemistry: \( \ce{CH4 + 2O2 -> CO2 + 2H2O} \), at
\( \SI{298.15}{\kelvin} \).

## Things to watch

- [x] the empty list returns null
- [x] a single node returns itself
- [ ] a cycle never terminates — detect it first
- [ ] `prev` must start as **null**, not as `head`

Pick one:

- (x) iterative
- ( ) recursive

## Nested structure

- Outer item with **bold** and a [link](https://example.com)
  - Inner item with `code`
    - Third level, still holding *emphasis*
  - Back to the second level
- Another outer item, with a fence of its own:

  ```dart
  assert(reverse(null) == null);
  ```

1. Ordered, outer
   1. Ordered, inner
   2. Sibling
2. Back out again

> If the list might contain a cycle, run Floyd's algorithm before reversing.
>
> > A quote inside a quote, with **bold** and `code` in it.
>
> See [the docs](https://example.com "Linked-list docs") or
> https://pub.dev for more, or the [reference][ref] section.

---

![A 120x60 placeholder](https://placehold.co/120x60/png)

Citations render as chips: the original result [1], and the follow-up [2].
Floyd's algorithm is a classic[^floyd], and the iterative form is the one
most standard libraries use[^stdlib].

That is everything. Ask if you want the recursive version too.

[1]: https://en.wikipedia.org/wiki/Linked_list
[2]: https://en.wikipedia.org/wiki/Cycle_detection
[ref]: https://example.com/reference

[^floyd]: Floyd's tortoise and hare finds a cycle in O(n) time and O(1)
    space.
[^stdlib]: Reversal is usually a library call in practice.
''';
