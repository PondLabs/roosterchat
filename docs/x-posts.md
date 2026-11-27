# X posts in the chat

A status link previews as an X card, laid out like iframely's: the author's avatar, name, verified mark and @handle, the X logo, the post's text, its media, the quoted post, and the date with reply, repost and like counts. The links are `x.com`, `twitter.com` and `mobile.` hosts, and the fxtwitter, vxtwitter, fixupx, fixvx and twittpr mirrors, in the `/<user>/status/<id>` form. Clicking the card opens the post. Links, @mentions and #hashtags in the text open on their own, and so does the quoted post.

`TwitterProvider` (`rooster/lib/client/components/video_embed/providers/twitter_provider.dart`) recognises the link and fetches the status. `XPost` (`.../video_embed/x_post.dart`) is the parsed status. `MatrixUrlPreviewComponent._xPostPreview` puts it on `UrlPreviewData.xPost`, and `UrlPreviewWidget._buildXCard` draws it. The post's text, and the quoted post's, is an `XPostText` (`rooster/lib/ui/molecules/x_post_text.dart`).

## Data: fxtwitter's API

`https://api.fxtwitter.com/<user>/status/<id>` returns the status as JSON without a key. Its `tweet` object has `author` (`name`, `screen_name`, `avatar_url`, `verification`, whose `type` is `individual`, `organization` or `government`; X draws an organization's check in gold), `text` (t.co links expanded, the trailing media link dropped), `media.all` (photos, videos, GIFs with size and thumbnail), `quote` (a nested status of the same shape), `created_timestamp`, `replies`, `retweets` and `likes`.

`text` is the whole text, also for X's long posts ("note tweets", up to 25,000 characters, marked `is_note_tweet`). `raw_text.facets` lists what X itself links in the text (`url`, `mention`, `hashtag`, with `symbol` for a cashtag and `bold`), by position in the text as posted, before the t.co links were expanded. The card does not read it; the end-to-end test holds the card's links against it.

A post that is not there is answered in two ways: `404` with `{"code":404,"message":"NOT_FOUND","tweet":null}`, or, for some ids, `200` with fxtwitter's HTML page. Neither parses to a status, so both fall back.

`media.all` lists every item in post order, whatever its kind, and the card reads only that list. Each item's `type` is `photo`, `video` or `gif`. A video has the MP4 of its best non-HEVC variant as `url`, its poster as `thumbnail_url` and its length in seconds as `duration`. A GIF has the same shape: an MP4 on `video.twimg.com/tweet_video/`, a poster, and `duration: 0`, since X gives it no length. A video fxtwitter finds no variant of arrives with `url: ""` (its `processMedia` falls back to the empty string). fxtwitter also sorts the items into `media.photos` and `media.videos`, which lose the order between the two kinds, and adds `media.mosaic` (one stitched image of a post's photos) and `media.external` (the player of a link in the text, such as a YouTube video); the card uses none of these.

The reply's `content-type` is `application/json` with no charset, and package:http would read that as Latin-1. The body is therefore decoded as UTF-8 by hand, so emoji and curly quotes survive.

It sends `access-control-allow-origin: *`, so native and web builds make the same request. `pbs.twimg.com` images and `video.twimg.com` MP4s echo the page's origin back, so they load on web too.

X's own `cdn.syndication.twimg.com/tweet-result`, the data behind the official embed, was not used. Checked on 29 live quote posts in October 2026, it and fxtwitter list the same media for the post and its quote. It only allows `https://platform.twitter.com` as an origin, and it needs a token computed from the id.

The status JSON is cached per status id in the provider, so the card, its video and its photos come from one request. A failed fetch is not cached. The preview component also caches the finished preview per URL.

## Text

The card shows the post's text whole when it takes 18 lines or fewer, as laid out at the card's width with the reader's text size. A longer text shows its first 12 lines over a **Show more** button, which shows the rest in place; **Show less** folds it back. The quoted post follows the same rule with smaller limits: whole up to 9 lines, else 6 under its own button. A text is never cut without that button (`XPostText`).

- **Why these numbers.** 470 recent posts from 13 accounts' timelines were laid out in the card's own text style in November 2026. None of the 386 ordinary ones (280 characters at most) took more than 15 lines, at the card's 480 px or at a phone's width, nor more than 18 on a phone with text at 1.3x: an ordinary post always shows whole. Of the 80 long posts, 32 passed 18 lines at the card's width. Of ten ordinary quoted posts, nine fit in 9 lines on a phone. A fold hides at least seven lines (four in a quote), never one or two behind a button.
- **Until November 2026** the text stopped at 12 lines and the quote at 4, with no button: 48 of those 470 posts were cut at the card's width, and six of the ten ordinary quotes on a phone. Where the cut fell on a line break, as in a post written as a list, Flutter drew no ellipsis either, and the card looked complete with its last lines missing (issue #359).
- **The buttons open nothing.** A tap on one folds or unfolds its own text. Anywhere else on the card still opens the post, and anywhere else in the quote the quote.
- **The reader's place.** The chat's timeline grows upward (`docs/chat-timeline.md`): a message that gets taller pushes its own top up. Unfolding a post there would show its end, a screen or more past where the reader was. So unfolding holds the text's first line where it is on screen, the rest opening below it, and folding holds the button where it is (`_XPostTextState._toggle`). The timeline then counts as scrolled up, with its "Jump to latest" button, as it would had the reader scrolled.
- **Links.** Links, @mentions and #hashtags are found by `XPost.linksIn`, in the folded and the unfolded text alike. A hashtag takes any script's letters, marks and digits. It used to be `#\w+`, and `\w` is ASCII in a Dart `RegExp`: `#notícias` was a link only up to `#not`, and opened that other hashtag. The quoted post's text has no links of its own: a tap on it opens the quote.

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
- A cashtag (`$NVDA`) is plain text, and so is what a long post has in bold.
- An @mention is any `@` followed by up to 15 letters, digits or underscores, whether or not X has that account.
- An unfolded post folds again when its message scrolls far enough away for the timeline to drop it.
- The plain preview, the fallback when the card cannot be made, holds one video: the post's first (`TwitterProvider.resolve`).
- fxtwitter is a third-party service. When it stops answering, posts fall back to the plain preview.

Check a status by hand:

```sh
curl -s -H 'Origin: https://example.com' -D - -o /dev/null \
  https://api.fxtwitter.com/SpaceX/status/1732824684683784516 | grep -i access-control
```

## End-to-end tests

Three layers, each closer to the real thing.

| Test | What it runs | Where it runs |
| --- | --- | --- |
| `rooster/unit_test/x_post_e2e_test.dart` | A status link through `TwitterProvider`, `MatrixUrlPreviewComponent` and `UrlPreviewWidget`, for 17 real posts from recorded replies | CI, with the unit tests |
| the same, with `--dart-define=X_E2E=live` | The same against the live `api.fxtwitter.com`, downloading every picture and video the card shows | By hand, and before changing the X card |
| `rooster/integration_test/chat/x_post_card_test.dart` | The app itself: alice sends status links to a room on the CI's Synapse and the timeline shows the cards | CI's integration tests |

**The pipeline test** writes no expectation per post. It reads the reply the provider was given and checks the card against it, at the card's full width and on a 360 px phone with text at 1.3x:

- the card holds the text as X has it, and shows all of it: at once, or behind a "Show more" that unfolds it, folds back, and opens nothing;
- every link, @mention and #hashtag in X's `raw_text.facets` is one link in the card, to the right place, and nothing else is a link;
- a cell for each photo, video and GIF, four at most with "+N" over the fourth, and behind each play button that item's own file;
- the quoted post the same way: author, text, media;
- the card itself still opens the post, and nothing overflows.

It also checks that every address people paste for one post (`x.com`, `twitter.com`, `mobile.`, the fxtwitter, vxtwitter, fixupx, fixvx and twittpr mirrors) gives one card from one request; that a post that is gone, in both of fxtwitter's answers, falls back to the plain preview; and that the timeline's own widget (`TimelineEventViewUrlPreviews`) shows the card for a message.

The 17 posts are one of each shape: a list of 15 short lines, long text alone, long text with a video, with a photo, a long post quoting one, a short post quoting a very long one, mentions and links, two, three, four and eleven photos, one, two and four videos, a photo with a video, a GIF, a reply. Their replies are in `rooster/unit_test/fixtures/x_e2e/<status id>.json`, as fxtwitter gave them, without each video's `formats` (every variant of the file, which the app does not read).

```sh
cd rooster
flutter test unit_test/x_post_e2e_test.dart                              # recorded
flutter test unit_test/x_post_e2e_test.dart --dart-define=X_E2E=live     # the live API
flutter test unit_test/x_post_e2e_test.dart --dart-define=X_E2E=record   # live, and rewrite the fixtures
```

**Live** asks the API itself, expects its `access-control-allow-origin: *`, and downloads what the card of each post shows the way the web build would, with an `Origin`: every picture the card draws at the size it draws it, and the first 64 kB of every video it plays. Each must come back as an image or `video/mp4` and allow the origin. A post that has been deleted fails its test with the API's answer: put another of its shape in the list and record. It is not part of CI: fxtwitter and X are not ours to keep up, and a red pipeline for their outage would say nothing about the code.

**The test in the app** makes fxtwitter's replies itself and gives them to a `TwitterProvider` registered in front of the app's own (`CompositeVideoProvider.registerProvider`), for the same reason. It checks what only the app can show: a message's link becomes a card in the room's real timeline, a post of 13 lines is all there, a post of 60 unfolds with its first line staying where it was on screen, and folds back.

The card's own tests (`x_post_card_test.dart`, `x_post_text_test.dart`) use smaller fixtures. The test fixture `rooster/unit_test/fixtures/x_status_fxtwitter.json` is SpaceX's video post with Ellen's Oscars selfie set as its quote. Both are trimmed from real replies. `x_status_quote_photos_fxtwitter.json` is a real quote post whose quoted post has two photos (rsa quoting TIDAL), trimmed. `x_status_eleven_photos_fxtwitter.json` is the post that announced the 20-photo limit, with 11 photos, trimmed. `x_status_two_videos_fxtwitter.json` is a SpaceX post with two videos, and `x_status_photo_video_fxtwitter.json` a CazéTV post with a photo followed by a video, both trimmed from real replies (2026-11-27).
