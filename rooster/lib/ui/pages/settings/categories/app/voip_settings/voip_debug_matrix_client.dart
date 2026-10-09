import 'dart:convert';

import 'package:rooster/client/alert.dart';
import 'package:rooster/client/matrix/components/voip/matrix_voip_component.dart';
import 'package:rooster/client/matrix/matrix_client.dart';
import 'package:rooster/ui/molecules/alert_view.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as mx;

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

class VoipDebugMatrixClient extends StatefulWidget {
  const VoipDebugMatrixClient(this.client, {super.key});
  final MatrixClient client;
  @override
  State<VoipDebugMatrixClient> createState() => _VoipDebugMatrixClientState();
}

class _VoipDebugMatrixClientState extends State<VoipDebugMatrixClient> {
  String messageVoipTurnNotConfigured(String homeserver) => Intl.message(
      "Your homeserver ($homeserver) does not have a TURN server configured",
      name: "messageVoipTurnNotConfigured",
      args: [homeserver],
      desc: "Warning in the WebRTC debug menu (developer settings) when the "
          "homeserver, whose address follows, offers no TURN server to route "
          "calls through. TURN is a name");

  String get labelVoipTurnError => Intl.message("TURN Error",
      name: "labelVoipTurnError",
      desc: "Title of the warning in the WebRTC debug menu (developer "
          "settings) when the homeserver has no TURN server. TURN is a name");

  String get labelVoipTurnServerHeader =>
      Intl.message("TURN Server (Homeserver Configuration)",
          name: "labelVoipTurnServerHeader",
          desc: "Header of the WebRTC debug menu's panel (developer settings) "
              "showing the TURN server the homeserver gives out. TURN is a "
              "name");

  String get promptVoipTestTurnServer => Intl.message("Test TURN Server",
      name: "promptVoipTestTurnServer",
      desc: "Button in the WebRTC debug menu (developer settings) that tries "
          "a connection through the homeserver's TURN server");

  String labelVoipTurnUsername(String username) =>
      Intl.message("username: $username",
          name: "labelVoipTurnUsername",
          args: [username],
          desc: "The TURN server's username in the WebRTC debug menu "
              "(developer settings), followed by its value");

  String labelVoipTurnPassword(String password) =>
      Intl.message("password: $password",
          name: "labelVoipTurnPassword",
          args: [password],
          desc: "The TURN server's password in the WebRTC debug menu "
              "(developer settings), followed by dots hiding it");

  String get labelVoipTurnConnectionTest => Intl.message("Connection Test",
      name: "labelVoipTurnConnectionTest",
      desc: "Header of the WebRTC debug menu's panel (developer settings) "
          "showing the results of the TURN server test");

  String get labelVoipTurnConnectingWithConfig =>
      Intl.message("Connecting with config:",
          name: "labelVoipTurnConnectingWithConfig",
          desc: "Header, in the WebRTC debug menu (developer settings), over "
              "the connection settings (JSON) the TURN server test uses");

  String get labelVoipTurnCandidates => Intl.message("Candidates",
      name: "labelVoipTurnCandidates",
      desc: "Header, in the WebRTC debug menu (developer settings), over the "
          "ICE candidates (network routes) the TURN server test found");

  String get labelVoipTurnCandidateError => Intl.message("ERROR",
      name: "labelVoipTurnCandidateError",
      desc: "Shown in the WebRTC debug menu (developer settings) in place of "
          "an ICE candidate that came without its text");

  String get labelVoipTurnOffer => Intl.message("Offer",
      name: "labelVoipTurnOffer",
      desc: "Header, in the WebRTC debug menu (developer settings), over the "
          "SDP offer the TURN server test made (the WebRTC session "
          "description)");

  bool loading = true;
  bool homeserverHasTurnServer = false;
  mx.TurnServerCredentials? credentials;
  webrtc.RTCPeerConnection? connection;
  List<webrtc.RTCIceCandidate> foundCandidates = List.empty(growable: true);
  webrtc.RTCSessionDescription? description;
  webrtc.RTCIceGatheringState? gatheringState;
  Map<String, dynamic>? connectionConfiguration;

  @override
  void initState() {
    super.initState();

    load();
  }

  @override
  void dispose() {
    connection?.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      var turnServer = await widget.client.getMatrixClient().getTurnServer();
      setState(() {
        credentials = turnServer;
        loading = false;
        homeserverHasTurnServer = true;
      });
    } catch (_) {
      setState(() {
        loading = false;
        homeserverHasTurnServer = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 500,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Column(
      children: [
        if (homeserverHasTurnServer == false)
          AlertView(Alert(AlertType.warning,
              messageGetter: () => messageVoipTurnNotConfigured(
                  widget.client.getMatrixClient().homeserver.toString()),
              titleGetter: () => labelVoipTurnError)),
        tiamat.Panel(
          mode: tiamat.TileType.surfaceContainerLow,
          header: labelVoipTurnServerHeader,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (credentials != null) showTurnServerCredentials(),
              testTurnServer(),
            ],
          ),
        )
      ],
    );
  }

  Widget testTurnServer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: tiamat.Button.secondary(
            text: promptVoipTestTurnServer,
            onTap: testTurn,
          ),
        ),
        if (connection != null) showTestConnectionInfo()
      ],
    );
  }

  Widget showTurnServerCredentials() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelLow(labelVoipTurnUsername(credentials!.username)),
        tiamat.Text.labelLow(
            labelVoipTurnPassword("•" * credentials!.password.length)),
        const tiamat.Seperator(),
        for (var item in credentials!.uris) tiamat.Text.labelLow(item)
      ],
    );
  }

  Widget showTestConnectionInfo() {
    return Column(
      children: [
        tiamat.Panel(
          mode: tiamat.TileType.surfaceContainerLow,
          header: labelVoipTurnConnectionTest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (connectionConfiguration != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                  child: tiamat.Panel(
                    mode: tiamat.TileType.surfaceContainerLow,
                    header: labelVoipTurnConnectingWithConfig,
                    child: tiamat.Text.tiny(const JsonEncoder.withIndent('  ')
                        .convert(connectionConfiguration!)
                        .replaceAll(credentials?.password ?? "",
                            "•" * (credentials?.password.length ?? 0))),
                  ),
                ),
              if (foundCandidates.isNotEmpty)
                tiamat.Panel(
                  header: labelVoipTurnCandidates,
                  mode: tiamat.TileType.surfaceContainerLowest,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var candidate in foundCandidates)
                          Padding(
                              padding: const EdgeInsets.all(8),
                              child: tiamat.Text.label(candidate.candidate ??
                                  labelVoipTurnCandidateError)),
                        if (gatheringState ==
                            webrtc.RTCIceGatheringState
                                .RTCIceGatheringStateGathering)
                          const Align(
                            alignment: Alignment.topCenter,
                            child: CircularProgressIndicator(),
                          )
                      ]),
                ),
              if (description != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                  child: tiamat.Panel(
                      header: labelVoipTurnOffer,
                      mode: tiamat.TileType.surfaceContainerLowest,
                      child: tiamat.Text.tiny(description!.sdp ?? "")),
                )
            ],
          ),
        )
      ],
    );
  }

  Future<void> testTurn() async {
    foundCandidates = List.empty(growable: true);

    var servers = credentials == null
        ? []
        : [
            {
              'username': credentials!.username,
              'credential': credentials!.password,
              'urls': List.from(credentials!.uris)
            },
          ];

    var configuration = <String, dynamic>{
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
    };

    var component = widget.client.getComponent<MatrixVoipComponent>();
    configuration = await component!.alterPeerConfiguration(configuration);

    setState(() {
      connectionConfiguration = configuration;
    });

    connection = await webrtc.createPeerConnection(configuration);

    var mediaConstraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': false
      },
      'video': false,
    };

    connection!.onIceCandidate = onIceCandidate;
    connection!.onIceGatheringState = onIceGatheringState;

    var media =
        await webrtc.navigator.mediaDevices.getUserMedia(mediaConstraints);
    for (var track in media.getTracks()) {
      await connection!.addTrack(track, media);
    }

    var offer = await connection!.createOffer({});
    await connection!.setLocalDescription(offer);
  }

  void onIceCandidate(webrtc.RTCIceCandidate candidate) {
    setState(() {
      foundCandidates.add(candidate);
    });
  }

  void onIceGatheringState(webrtc.RTCIceGatheringState state) {
    setState(() {
      gatheringState = state;
    });
  }
}
