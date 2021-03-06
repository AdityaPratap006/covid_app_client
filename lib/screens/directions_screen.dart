import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location_permissions/location_permissions.dart';

//Widgets
import '../widgets/directions_search_box.dart';
import '../widgets/direction_legends.dart';

//Providers
import '../providers/directions.dart';
import '../providers/hotspot_locations.dart';

//Utils
import '../utils/search_box_decoration.dart';
import '../utils/polyline.dart';

class DirectionsScreen extends StatefulWidget {
  @override
  _DirectionsScreenState createState() => _DirectionsScreenState();
}

class _DirectionsScreenState extends State<DirectionsScreen> {
  GoogleMapController _mapController;
  bool _loadingDirections = false;
  bool _currentLocationLoading = false;
  LatLng _currentLocation;
  double _cameraBearing = 0.0;
  LatLng _cameraTarget = LatLng(23, 79);
  double _cameraZoom = 14;
  Set<Marker> _markers = Set();

  void _onMapCreated(GoogleMapController controller) {
    setState(() {
      _mapController = controller;
    });
  }

  void _showCustomDialog({String title, String content, Function action}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          FlatButton(
            child: Text('OK'),
            onPressed: () {
              Navigator.of(ctx).pop();

              if (action != null) {
                action();
              }
            },
          )
        ],
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _currentLocationLoading = true;
    });

    final Geolocator geolocator = Geolocator()..forceAndroidLocationManager;
    GeolocationStatus status =
        await geolocator.checkGeolocationPermissionStatus();

    if (status != GeolocationStatus.granted) {
      _showCustomDialog(
        title: 'Can\'t access Location!',
        content: 'Turn on the location permissions for Covid Radar.',
        action: () async {
          await LocationPermissions().openAppSettings();
        },
      );
    } else {
      try {
        if (_currentLocation == null) {
          Position pos = await geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
          );

          BitmapDescriptor myMarkerIcon = await BitmapDescriptor.fromAssetImage(
            ImageConfiguration(),
            'lib/assets/images/user_location.png',
          );

          setState(() {
            _currentLocation = LatLng(pos.latitude, pos.longitude);
            _markers.add(
              Marker(
                markerId: MarkerId('my_location'),
                icon: myMarkerIcon,
                position: LatLng(pos.latitude, pos.longitude),
                infoWindow: InfoWindow(
                  title: 'My Location',
                ),
              ),
            );
          });
        }

        await _mapController.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _currentLocation,
              zoom: 16.0,
            ),
          ),
        );
      } catch (error) {
        _showCustomDialog(
          title: 'An error occurred!',
          content: error.toString(),
        );
      }
    }

    setState(() {
      _currentLocationLoading = false;
    });
  }

  Future<void> _drawRoutes({String source, String destination}) async {
    var hotspotLocations =
        Provider.of<HotspotLocations>(context, listen: false).locations;
    var directionsApi = Provider.of<DirectionsProvider>(context, listen: false);

    directionsApi.clearMarkers();
    directionsApi.clearRoutes();

    setState(() {
      _loadingDirections = true;
    });

    await directionsApi.findDirections(
      src: source,
      dest: destination,
      hotspotLocations: hotspotLocations.map((loc) {
        return LatLng(loc.coordinates.latitude, loc.coordinates.longitude);
      }).toList(),
    );

    LatLng srcCoord = directionsApi.sourceCoord;
    LatLng destCoord = directionsApi.destinationCoord;
    LatLng midPoint = LatLng((srcCoord.latitude + destCoord.latitude) / 2,
        (srcCoord.longitude + destCoord.longitude) / 2);
    // LatLngBounds bounds = LatLngBounds(northeast: srcCoord, southwest: destCoord);

    double distance = calculateDistanceKM(srcCoord.latitude, srcCoord.longitude,
        destCoord.latitude, destCoord.longitude);
    double zoom;
    if (distance >= 2000) {
      zoom = 4;
    } else if (distance >= 1000 && distance < 2000) {
      zoom = 5;
    } else if (distance >= 500 && distance < 1000) {
      zoom = 6;
    } else if (distance >= 250 && distance < 500) {
      zoom = 7;
    } else if (distance >= 100 && distance < 250) {
      zoom = 8;
    } else if (distance >= 50 && distance < 100) {
      zoom = 9;
    } else if (distance >= 10 && distance < 50) {
      zoom = 10;
    } else {
      zoom = 11;
    }

    // await _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 10.0));
    await _mapController
        .animateCamera(CameraUpdate.newLatLngZoom(midPoint, zoom));
    setState(() {
      _loadingDirections = false;
    });
  }

  @override
  void initState() {
    var directionsApi = Provider.of<DirectionsProvider>(context, listen: false);
    directionsApi.clearMarkers();
    directionsApi.clearRoutes();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final deviceSize = MediaQuery.of(context).size;
    // final directionsApi = Provider.of<DirectionsProvider>(
    //   context,
    //   listen: false,
    // );
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Container(
            width: deviceSize.width,
            height: deviceSize.height,
            child: Consumer<DirectionsProvider>(
              builder: (ctx, directionsApi, _) => GoogleMap(
                mapType: MapType.normal,
                buildingsEnabled: true,
                initialCameraPosition: CameraPosition(
                  target: LatLng(23, 79),
                  zoom: 5,
                ),
                onMapCreated: _onMapCreated,
                polylines: directionsApi.currentRoute,
                markers: {...directionsApi.markers, ..._markers},
                onCameraMove: (CameraPosition pos) {
                  setState(() {
                    _cameraBearing = pos.bearing;
                    _cameraTarget = pos.target;
                    _cameraZoom = pos.zoom;
                  });
                },
              ),
            ),
          ),
          DirectionsSearchBox(
            drawRoutes: _drawRoutes,
            loading: _loadingDirections,
          ),
          Positioned(
            bottom: 30,
            left: 8,
            child: Consumer<DirectionsProvider>(
              builder: (ctx, directionsApi, _) => Visibility(
                visible: directionsApi.currentRoute.isNotEmpty,
                child: DirectionLegends(),
              ),
            ),
          ),
          Positioned(
            top: 200.0,
            right: 8.0,
            child: FloatingActionButton(
              onPressed: () {
                if (_currentLocationLoading) {
                  return;
                }

                _getCurrentLocation();
              },
              backgroundColor: Theme.of(context).primaryColor,
              splashColor: Theme.of(context).accentColor,
              child: Icon(Icons.location_searching),
            ),
          ),
          Positioned(
            top: 280.0,
            right: 8.0,
            child: FloatingActionButton(
              child: Transform.rotate(
                angle: -(pi / 180) * _cameraBearing,
                child: Icon(Icons.navigation),
              ),
              backgroundColor: Theme.of(context).primaryColor,
              splashColor: Theme.of(context).accentColor,
              onPressed: () async {
                setState(() {
                  _cameraBearing = 0.0;
                });
                await _mapController.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(
                      target: _cameraTarget,
                      bearing: 0.0,
                      zoom: _cameraZoom,
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 50,
            bottom: 50,
            left: 15,
            right: 15,
            child: Visibility(
              visible: _loadingDirections,
              child: Container(
                alignment: Alignment.center,
                width: double.infinity,
                height: deviceSize.height - 150,
                decoration: SearchBoxDecoration.decoration(),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 40,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(),
                      ),
                      SizedBox(
                        height: 20,
                      ),
                      Text(
                        'Determining routes and analysing their safety',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(
                        height: 20,
                      ),
                      Text(
                        'Routes more than 500km long take a while to be analysed, please wait...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).accentColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ), 
        ],
      ),
    );
  }
}
