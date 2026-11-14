# X posts in the chat

A status link previews as an X card, laid out like iframely's: the author's avatar, name, verified mark and @handle, the X logo, the post's text, its media, the quoted post, and the date with reply, repost and like counts. The links are `x.com`, `twitter.com` and `mobile.` hosts, and the fxtwitter, vxtwitter, fixupx, fixvx and twittpr mirrors, in the `/<user>/status/<id>` form. Clicking the card opens the post. Links, @mentions and #hashtags in the text open on their own, and so does the quoted post.

`TwitterProvider` (`rooster/lib/client/components/video_embed/providers/twitter_provider.dart`) recognises the link and fetches the status. `XPost` (`.../video_embed/x_post.dart`) is the parsed status. `MatrixUrlPreviewComponent._xPostPreview` puts it on `UrlPreviewData.xPost`, and `UrlPreviewWidget._buildXCard` draws it.

## Data: fxtwitter's API

`https://api.fxtwitter.com/<user>/status/<id>` returns the status as JSON without a key. Its `tweet` object has `author` (`name`, `screen_name`, `avatar_url`, `verification`, whose `type` is `individual`, `organization` or `government`; X draws an organization's check in gold), `text` (t.co links expanded, the trailing media link dropped), `media.all` (photos, videos, GIFs with size and thumbnail), `quote` (a nested status of the same shape), `created_timestamp`, `replies`, `retweets` and `likes`.

The reply's `content-type` is `application/json` with no charset, and package:http would read that as Latin-1. The body is therefore decoded as UTF-8 by hand, so emoji and curly quotes survive.

It sends `access-control-allow-origin: *`, so native and web builds make the same request. `pbs.twimg.com` images and `video.twimg.com` MP4s echo the page's origin back, so they load on web too.

X's own `cdn.syndication.twimg.com/tweet-result`, the data behind the official embed, was not used. Checked on 29 live quote posts in October 2026, it and fxtwitter list the same media for the post and its quote. It only allows `https://platform.twitter.com` as an origin, and it needs a token computed from the id.

The status JSON is cached per status id in the provider, so the card, its video and its photos come from one request. A failed fetch is not cached. The preview component also caches the finished preview per URL.

## Media

- **Photos:** one photo keeps its shape. Two to four photos show in X's grid. Since 2026-11-12 X allows 20 photos and videos per post; a post with more than four shows its first four, the fourth dimmed under a "+N" with the count of the rest (the official embed shows six with no count, x.com a sideways strip). Tapping a photo, or the "+N", opens the lightbox with every photo, on the photo tapped.
- **Video or GIF:** the thumbnail with a play button. Play opens the MP4 in the video dialog, the same player as an X video link had before.
- **Quoted post:** a nested card laid out like X's official embed (`platform.twitter.com/embed/Tweet.html`): author and text, then every photo, video and GIF of the quote edge to edge. One item keeps its shape (cropped at 300 px tall). Two sit side by side, three are one tall item next to two stacked, four are a 2x2; two to four always fill a 16:9 box. A photo opens the lightbox with the quote's photos, a video or GIF plays in the video dialog, anywhere else opens the quote. Until October 2026 the quote showed only its first item, so the second photo of a quote went missing. A quote with more than four items shows its first four in the same 16:9 box, the fourth under "+N". When the fourth and every hidden item are photos, the "+N" opens the lightbox on the fourth; when a video or GIF is among them it opens the quote on X instead, since the lightbox pages photos only.
- **Sizes:** fxtwitter hands out each photo at `name=orig`, the upload itself: about 2 MB for a 3840x2560 photo, and 39 MB once decoded, so four cells took more than Flutter's 100 MB image cache. `pbs.twimg.com` serves every photo at other sizes too, picked by the `name` parameter: `small` (680 px on the long side), `medium` (1200), `large` (2048). `XPhotoSize` rewrites only `pbs.twimg.com/media/` URLs, keeping their other parameters. Grid cells draw `small`, a post's only photo `medium`, and the lightbox `large`, with the cell's copy shown until it loads (`UrlPreviewImage.full`, `Lightbox.galleryThumbnails`). Avatars, video and GIF posters (which answer every `name` with the same file) and other sites' photos (Instagram's are signed URLs) are used as they are. The warm-up loads exactly what the card draws (`UrlPreviewComponent.cardImages`).
- **Lightbox:** pages with the arrows on screen or on the keyboard, says which photo it shows ("4 / 11"), downloads the photos on either side, and gives each photo its own shape as soon as it is stepped to (from the post's width and height), before it has loaded.

## Fallback

If the fetch fails (fxtwitter down, a private or deleted post), the link goes through the usual path: the homeserver's URL preview, then the provider's plain video or photo preview. In an end-to-end encrypted room with URL previews turned off, X links are still read from fxtwitter, as they were before the card. The homeserver is never asked.

## Limitations

- A post with both photos and a video shows only the photos, and its "+N" counts only photos, the ones the lightbox can show. A quoted post shows both. With 20 items a post, mixed posts will be more common; drawing the main card's media like the quote's is the next step.
- The lightbox cannot be swiped from photo to photo; the arrows do it. A swipe would compete with its zoom and drag gestures.
- The card shows no polls, community notes, reply context or link cards.
- fxtwitter is a third-party service. When it stops answering, posts fall back to the plain preview.

Check a status by hand:

```sh
curl -s -H 'Origin: https://example.com' -D - -o /dev/null \
  https://api.fxtwitter.com/SpaceX/status/1732824684683784516 | grep -i access-control
```

The test fixture `rooster/unit_test/fixtures/x_status_fxtwitter.json` is SpaceX's video post with Ellen's Oscars selfie set as its quote. Both are trimmed from real replies. `x_status_quote_photos_fxtwitter.json` is a real quote post whose quoted post has two photos (rsa quoting TIDAL), trimmed. `x_status_eleven_photos_fxtwitter.json` is the post that announced the 20-photo limit, with 11 photos, trimmed.
