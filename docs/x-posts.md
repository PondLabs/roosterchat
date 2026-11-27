# X posts in the chat

A status link previews as an X card, laid out like iframely's: the author's avatar, name, verified mark and @handle, the X logo, the post's text, its media, the quoted post, and the date with reply, repost and like counts. The links are `x.com`, `twitter.com` and `mobile.` hosts, and the fxtwitter, vxtwitter, fixupx, fixvx and twittpr mirrors, in the `/<user>/status/<id>` form. Clicking the card opens the post. Links, @mentions and #hashtags in the text open on their own, and so does the quoted post.

`TwitterProvider` (`rooster/lib/client/components/video_embed/providers/twitter_provider.dart`) recognises the link and fetches the status. `XPost` (`.../video_embed/x_post.dart`) is the parsed status. `MatrixUrlPreviewComponent._xPostPreview` puts it on `UrlPreviewData.xPost`, and `UrlPreviewWidget._buildXCard` draws it.

## Data: fxtwitter's API

`https://api.fxtwitter.com/<user>/status/<id>` returns the status as JSON without a key. Its `tweet` object has `author` (`name`, `screen_name`, `avatar_url`, `verification`, whose `type` is `individual`, `organization` or `government`; X draws an organization's check in gold), `text` (t.co links expanded, the trailing media link dropped), `media.all` (photos, videos, GIFs with size and thumbnail), `quote` (a nested status of the same shape), `created_timestamp`, `replies`, `retweets` and `likes`.

`media.all` lists every item in post order, whatever its kind, and the card reads only that list. Each item's `type` is `photo`, `video` or `gif`. A video has the MP4 of its best non-HEVC variant as `url`, its poster as `thumbnail_url` and its length in seconds as `duration`. A GIF has the same shape: an MP4 on `video.twimg.com/tweet_video/`, a poster, and `duration: 0`, since X gives it no length. A video fxtwitter finds no variant of arrives with `url: ""` (its `processMedia` falls back to the empty string). fxtwitter also sorts the items into `media.photos` and `media.videos`, which lose the order between the two kinds, and adds `media.mosaic` (one stitched image of a post's photos) and `media.external` (the player of a link in the text, such as a YouTube video); the card uses none of these.

The reply's `content-type` is `application/json` with no charset, and package:http would read that as Latin-1. The body is therefore decoded as UTF-8 by hand, so emoji and curly quotes survive.

It sends `access-control-allow-origin: *`, so native and web builds make the same request. `pbs.twimg.com` images and `video.twimg.com` MP4s echo the page's origin back, so they load on web too.

X's own `cdn.syndication.twimg.com/tweet-result`, the data behind the official embed, was not used. Checked on 29 live quote posts in October 2026, it and fxtwitter list the same media for the post and its quote. It only allows `https://platform.twitter.com` as an origin, and it needs a token computed from the id.

The status JSON is cached per status id in the provider, so the card, its video and its photos come from one request. A failed fetch is not cached. The preview component also caches the finished preview per URL.

## Media

A post's media is one of three layouts, picked from what it holds. Every item shows in all of them:

| The post holds | Layout | Drawn by |
| --- | --- | --- |
| photos only | one photo at its shape, or the photo grid | `image()`, `_buildPhotoGrid` |
| one video or one GIF | the video thumbnail | `_buildVideoThumbnail` |
| two or more items with a video or GIF among them (`XPost.hasVideoGrid`) | the photo grid's layout, a cell for each item | `_xPostMedia` |

- **Photos:** one photo keeps its shape. Two to four photos show in X's grid. Since 2026-11-12 X allows 20 photos and videos per post; a post with more than four shows its first four, the fourth dimmed under a "+N" with the count of the rest (the official embed shows six with no count, x.com a sideways strip). Tapping a photo, or the "+N", opens the lightbox with every photo, on the photo tapped.
- **One video or GIF:** the thumbnail with a play button, and the video's length in the corner, or "GIF" for a GIF. Play opens the MP4 in the video dialog, the same player as an X video link had before.
- **Several videos, or photos next to a video or GIF:** the same grid as the photos (two side by side, three as one large cell next to two stacked, four as a 2x2, more than four as four with "+N"), in post order. A photo's cell opens the lightbox on that photo, which pages through the post's photos. A video's or GIF's cell shows its poster under a play mark, with its length or "GIF" in the corner, and the whole cell plays that item in the video dialog (`TwitterProvider.videoOf`). The "+N" follows the quote's rule: when the fourth item and every hidden one are photos it opens the lightbox on the fourth, and when a video or GIF is among them it opens the post on X. Until November 2026 the card had no such grid: a post with two videos showed the first one, and a post with photos and a video showed only the photos (issue #356).
- **A video without a file:** fxtwitter sends an empty `url` for a video it finds no variant of. In a grid the item is its poster alone, with no play mark, and a tap on it opens the post, as a tap anywhere else on the card does. As a post's only item it keeps the thumbnail, and its play button opens the dialog's "unavailable" view, which offers the browser.
- **Quoted post:** a nested card laid out like X's official embed (`platform.twitter.com/embed/Tweet.html`): author and text, then every photo, video and GIF of the quote edge to edge. One item keeps its shape (cropped at 300 px tall). Two sit side by side, three are one tall item next to two stacked, four are a 2x2; two to four always fill a 16:9 box. A photo opens the lightbox with the quote's photos, a video or GIF plays in the video dialog, anywhere else opens the quote. Until October 2026 the quote showed only its first item, so the second photo of a quote went missing. A quote with more than four items shows its first four in the same 16:9 box, the fourth under "+N". When the fourth and every hidden item are photos, the "+N" opens the lightbox on the fourth; when a video or GIF is among them it opens the quote on X instead, since the lightbox pages photos only.
- **Sizes:** fxtwitter hands out each photo at `name=orig`, the upload itself: about 2 MB for a 3840x2560 photo, and 39 MB once decoded, so four cells took more than Flutter's 100 MB image cache. `pbs.twimg.com` serves every photo at other sizes too, picked by the `name` parameter: `small` (680 px on the long side), `medium` (1200), `large` (2048). `XPhotoSize` rewrites only `pbs.twimg.com/media/` URLs, keeping their other parameters. Grid cells draw `small`, a post's only item `medium` when it is a photo (a photo next to a video is in a grid, so `small`), and the lightbox `large`, with the cell's copy shown until it loads (`UrlPreviewImage.full`, `Lightbox.galleryThumbnails`). `XPost.cellImageUrl` decides, for the card and the warm-up alike. Avatars, video and GIF posters (which answer every `name` with the same file) and other sites' photos (Instagram's are signed URLs) are used as they are. The warm-up loads exactly what the card draws (`UrlPreviewComponent.cardImages`): for a grid with a video in it, its first four cells in post order, posters included.
- **Lightbox:** pages with the arrows on screen or on the keyboard, says which photo it shows ("4 / 11"), downloads the photos on either side, and gives each photo its own shape as soon as it is stepped to (from the post's width and height), before it has loaded.

## Fallback

If the fetch fails (fxtwitter down, a private or deleted post), the link goes through the usual path: the homeserver's URL preview, then the provider's plain video or photo preview. In an end-to-end encrypted room with URL previews turned off, X links are still read from fxtwitter, as they were before the card. The homeserver is never asked.

## Limitations

- A post with more than four items shows four. When a video or GIF is among the hidden ones, the "+N" opens the post on X rather than anything in the app: the lightbox pages photos only, and the video dialog plays one video.
- A video or GIF plays in the video dialog, not in the card; a GIF is a short MP4 there, with the player's controls.
- The lightbox cannot be swiped from photo to photo; the arrows do it. A swipe would compete with its zoom and drag gestures.
- The card shows no polls, community notes, reply context or link cards. A link's own player (`media.external`, such as a YouTube video linked in the text) is a link card too: the link in the text opens it.
- The plain preview, the fallback when the card cannot be made, holds one video: the post's first (`TwitterProvider.resolve`).
- fxtwitter is a third-party service. When it stops answering, posts fall back to the plain preview.

Check a status by hand:

```sh
curl -s -H 'Origin: https://example.com' -D - -o /dev/null \
  https://api.fxtwitter.com/SpaceX/status/1732824684683784516 | grep -i access-control
```

The test fixture `rooster/unit_test/fixtures/x_status_fxtwitter.json` is SpaceX's video post with Ellen's Oscars selfie set as its quote. Both are trimmed from real replies. `x_status_quote_photos_fxtwitter.json` is a real quote post whose quoted post has two photos (rsa quoting TIDAL), trimmed. `x_status_eleven_photos_fxtwitter.json` is the post that announced the 20-photo limit, with 11 photos, trimmed. `x_status_two_videos_fxtwitter.json` is a SpaceX post with two videos, and `x_status_photo_video_fxtwitter.json` a CazéTV post with a photo followed by a video, both trimmed from real replies (2026-11-27).
