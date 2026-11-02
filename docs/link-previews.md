# Link previews

A message's first link gets a preview card under it. The goal is that a link
you send shows its card at the same moment the message appears.

## Where a preview comes from

`MatrixUrlPreviewComponent`
(`rooster/lib/client/matrix/components/url_preview/matrix_url_preview_component.dart`)
makes the preview itself where it can. It asks the homeserver's
`preview_url` only for pages it cannot read:

| Link | Source | Homeserver asked |
| --- | --- | --- |
| An image file (`.png`, `.jpg`, ...) | the image itself (`DirectImageLink`) | no |
| An X status | fxtwitter's JSON API (see [x-posts.md](x-posts.md)) | only if fxtwitter fails |
| YouTube | YouTube's oEmbed, and the thumbnail from `i.ytimg.com` | no |
| A video file (`.mp4`, `.webm`, ...) | the link itself, no request | no |
| Instagram | the homeserver, and Instagram's embed page at the same time (see [instagram-reels.md](instagram-reels.md)) | yes |
| Any other page | the homeserver | yes |

A YouTube oEmbed reply takes a few hundred milliseconds. Before it can answer,
the homeserver downloads the whole watch page (well over a megabyte) and the
thumbnail. The YouTube card shows the title, "by" the channel, and the
thumbnail. It does not show the video's description.

fxtwitter, YouTube's oEmbed and `i.ytimg.com` all send
`access-control-allow-origin`, so web and native builds make the same
requests. Instagram's embed page can only be read on native builds. On web
an Instagram card comes from the homeserver alone.

In an end-to-end encrypted room with URL previews turned off, the homeserver
is never asked. Image links, X, YouTube, Instagram and video files are still
previewed, because those requests never go through the homeserver.

## When it is fetched

1. **While you write.** The composer's `UrlPreviewPrefetcher`
   (`rooster/lib/ui/organisms/chat/url_preview_prefetcher.dart`) fetches the
   message's first link once the text has rested for 300 ms. It also loads the
   card's images into Flutter's image cache: the photo grid, the image or
   video thumbnail, and an X author's avatar. It only fetches what the
   timeline would preview for the sent message. That excludes rooms with
   media previews off, matrix.to links, links without a domain, and pages in
   an encrypted room with URL previews off.
2. **When you press send.** Whatever the composer has not fetched yet starts
   before the message is processed and encrypted.
3. **From the local echo.** `TimelineEventViewUrlPreviews` asks for the
   preview as soon as the message appears, while it is still being sent. It
   does not wait for the homeserver to echo the message back. A message that
   failed to send is not fetched until it is sent again.

All three ask the same component, and the component makes one request per
link. Asking while a request is under way waits for that request. A finished
preview is kept for the session, keyed by the link. A link that got no
preview is kept as `UrlPreviewComponent.invalidPreviewData` and is not asked
for again. A pinned message, a search result or a notification with the same
link reuses the same preview.

The timeline takes the link from the sent event's formatted body. In that
HTML an `&` is written `&amp;`, so `MatrixTimelineEventMessage.getLinks`
unescapes the body first. Otherwise the timeline would look up a different
link than the one the composer fetched.

## Showing it

The card shows as soon as its text is known. Images do not hold the card
back. Each image fades in over the space kept for it:

- A video thumbnail is in a box of the video's shape (16:9 unless the
  provider says otherwise).
- X and Instagram photos come with their sizes.
- A homeserver preview's image uses `og:image:width` and `og:image:height`.
- An image link has no size until it loads. It holds a 16:9 box of up to 480
  pixels until then.

An image that fails to load leaves its space empty, not a broken-image mark.

## Privacy

Prefetching sends the link to the same places the sent message's preview
would: the homeserver, fxtwitter, YouTube or Instagram. It does so a moment
earlier. A link you type and then delete without sending may already have
been fetched. Telegram, Signal and WhatsApp preview links while you type in
the same way.
