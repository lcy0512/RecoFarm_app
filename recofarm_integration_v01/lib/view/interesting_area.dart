import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
// import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:get/route_manager.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:new_recofarm_app/view/my_area_list.dart';
import 'package:new_recofarm_app/view/myarea_edit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

/*
  Description : Google map 나의 관심 소재지 등록하기 페이지 
  Date        : 2024.04.21 Sun
  Author      : Forrest DongGeun Park. (PDG)
  Updates     : 
	  2024.04.21 Sun by pdg
		  - google map 추가 및 ios minimum version 14 로 변환 
      - footter 디자인 + 내 관심 경작지로 이동하기 ( 우선 엘리베이트 버튼으로 구현 )
      - 내위치 권한 인증 및 내위치로 첫 지도 카메라 위치 이동 시키기 
      - 위치 권한이 없을 경우 앱을 사용하지 못하는 쪽으로 설계를 하자. 
      - 특정 위치 마커 그리기 
      - 특정 위치 를 기준으로 나의 경작지 면적 을 반경으로 지도위에 표시 하기 
      - geo coding package 를 활용하여 주소 검색 을 해보자. 
        -> json 형태로 주소를 받아오기때문에 http 가 필요함. 
      - 소재지 주소 검색하여 경작지 위치로 이동하는것 완료
      - 소재지에서 관심 작물을 키울때 예측 생산량 보여주는 버튼을 만들어야함. 
      - 지도에서 클릭 했을때 마커 위치 변경하고 해당위치에서의 경작지 면적을 입력받아 반경그림 추가하고 위치경작정보를 누르면
      - 페이지 이동

      2024.04.22 by pdg
        - 처음 페이지 가 현재 내 위치로 나오게 수정?
        - 내 관심 농작지 List view 로 보여주는 기능 필요 ?
        - 내 관심 농작지 페이지 list view 로 보여주는 페이지 를 제작 <- db 조회 필요..
        - sql db 에서 가져와서 listview 로 플랏 해주고 
      2024.04.23 by pdg
        - shared pref 설정 세팅 및 함수 정리 
        - 관심농지로 추가 버튼 눌렀을때  재배작물과 면적을 입력받도록 하자. 
        - floating action button 을 사용해서 현재위치로 바로가기 기능을 만들자. 
      2024.04.24 by pdg 
        - 지도에 마커 뜨도록 하는 기능 
          -> 마커 색상 변경
        - 롱탭하여 관심농지로 추가누르면 마커색이 빨간색으로 변함.  
        - 현재위치로 돌아가는 floating action button 추가 

  Detail      : - 

*/
class InterestingAreaPage extends StatefulWidget {
  const InterestingAreaPage({super.key});

  @override
  State<InterestingAreaPage> createState() => _InterestingAreaPageState();
}

class _InterestingAreaPageState extends State<InterestingAreaPage> {
  // properties
  late int longTapCounter;

  late int currentLocGetCallCount;
  late TextEditingController locationTfController;
  // Geometric properties
  late LatLng? curLoc; // 현재 위치 위도경도
  late LatLng interestLoc; // 관심 위치 위도 경도 ( 검색시 입력값이 들어감. )
  late bool islocationEnable; // 지도 권한 ok -> true
  // Marker
  late Marker curLocMarker; // 현재위치 마커
  late Marker myloc1; // 기본
  late Marker? findMarker; // 검색한 위치의 마커

  late Circle myAreaCircle;
  late double myAreaMeterSquare;
  late double myAreaRadius;
  late double distance1;

  // 검색한 주소의 Formatted address
  late String searchedAddress;
  // google map 컨트롤러!!
  late GoogleMapController mapController;
  // markers
  late List markers; // 내가 검색한 장소들이 다 들어가 있음.
  late Set<Marker> selectedAreaMarker;
  late List myareaMarkerList;
  // myarea
  late List myareaData;

  // -----------------update 2024.04.23 below-----------------
  // shared pref instance init
  late SharedPreferences prefs;
  // User info
  late String userId;
  // my area product
  late String myareaProduct;
  // my area Address(formmatted)
  late String myareaAddress;

  //관심 소재지에서 면적 입력 받는 변수
  late double myareaSize;

  late TextEditingController myareaSizeTFcontroller;
  late TextEditingController myareaProductTFcontroller;

  // Init STATE-------------------------------
  @override
  void initState() {
    super.initState();

    longTapCounter = 0;

    // selected area( long tap setting ) -> 선택한 지역의 마커는 페이지 실행될때마다 초기화 됨.
    selectedAreaMarker = {};

    // 현재위치 파악
    currentLocGetCallCount = 0;
    curLoc = null;
    _curPositiongGet(); // ->  curLoc
    _curPosGenCalcDistance();
    _curLocAddressGet();

    // 검색한곳 마커
    findMarker = null;
    // 면적과 품종을 입력받을 text field init
    myareaSizeTFcontroller = TextEditingController(text: "");
    myareaProductTFcontroller = TextEditingController(text: "");

    // mysql variable init
    userId = "";
    myareaProduct = "";
    myareaMarkerList = [];
    locationTfController = TextEditingController(text: "");
    interestLoc = const LatLng(36.595086846, 128.9351767475763);
    //print(interestLoc);

    // 경작지 위치  마커
    myloc1 = Marker(
      markerId: const MarkerId("경작지1"),
      position: interestLoc,
      infoWindow: const InfoWindow(
        title: "내 경작지1",
        snippet: "배추밭, 10000제곱 미터",
      ),
    );

    // 마커 리스트
    markers = [myloc1];
    myAreaMeterSquare = 10000; // 100 m^2 -> 3.14 * r^2 =100 ->
    myAreaRadius = sqrt(myAreaMeterSquare / 3.14);
    // 경작지 반경 계산
    myAreaCircle = Circle(
      circleId: CircleId('myloc1'),
      center: interestLoc,
      fillColor: Colors.blue.withOpacity(0.4),
      radius: myAreaRadius,
      strokeColor: Colors.blue,
      strokeWidth: 1,
    );

    // 경작지1 과 현재 위치 간 거리 계산
    distance1 = 0;
    //getPlaceAddress(interestLoc.latitude, interestLoc.longitude);
    // 농작할 소재지 검색
    searchedAddress = "";
    getPlaceAddress(interestLoc.latitude, interestLoc.longitude);
    //searchPlace();

    // 내 경작지 데이터
    myareaData = [];
    // user Id fetching and myarea access
    _getUserIdFromSharedPref();

    //_getMyareaJSONData();

    // 현재 지정된 위치(위도 경도)를 my sql Insert
    _curPosGenCalcDistance();
    //print(" 현재위치의 위도 경도는 ${curLoc!.latitude}, ${curLoc!.latitude} 입니다 ");
    // 현재 위치  마커
    _basicMarkershow();
  }

////////////////////// [Screen build] ////////////////////
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: Colors.amber[100],
        actions: [
          IconButton(
              onPressed: () {
                // 소재지 검색 함수
                searchPlace();
              },
              icon: Icon(Icons.search_outlined))
        ],
        title: SingleChildScrollView(
          child: PreferredSize(
            preferredSize: Size.fromHeight(100),
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.7,
              height: 60,
              child: TextField(
                textAlign: TextAlign.start,
                decoration: const InputDecoration(
                  // alignLabelWithHint: true,
                  focusedBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: Color.fromARGB(255, 223, 117, 110))),
                  floatingLabelAlignment: FloatingLabelAlignment.start,
                  labelText: " 소재지 주소 검색",
                  labelStyle: TextStyle(
                    color: Color.fromARGB(255, 235, 150, 31),
                    shadows: CupertinoContextMenu.kEndBoxShadow,
                    letterSpacing: 4,
                    //textBaseline: TextBaseline.ideographic
                  ),
                ),
                controller: locationTfController,
              ),
            ),
          ),
        ),
      ),

      // check permission 함수는 future 함수이므로 future builder 를 사용하는 것이 좋다.
      body: FutureBuilder<String>(
        future: checkPermission(),
        builder: (context, snapshot) {
          // 권한 정보가 스냅샷에 없을때  혹은 커넥션을 기다리고 있을때
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          if (snapshot.data == "위치 권한이 허가 되었습니다.") {
            _curPositiongGet();

            ///----------------------------------<< Screen 화면 >>------------------------------------------
            return Column(
              children: [
                Text(
                  "길게 눌러서 지역을 선택하세요",
                  style: TextStyle(color: Colors.purple, fontSize: 20),
                ),
                curLoc == null
                    ? Center(
                        child: CircularProgressIndicator(),
                      )
                    // Google map view
                    : Expanded(
                        flex: 2, // 화면 2분할
                        child: GoogleMap(
                            //mapType: MapType.normal,
                            //buildingsEnabled: true,
                            onLongPress: (postion) =>
                                _longTapSelectPosition(postion),
                            initialCameraPosition: CameraPosition(
                              // 최초 맵 시작지점 <- 내현재위치 .
                              target: curLoc!,
                              zoom: 14.4746,
                            ),
                            // myLocationButtonEnabled: true,
                            // compassEnabled: true,
                            // zoomGesturesEnabled: true,
                            // rotateGesturesEnabled: true,
                            // mapToolbarEnabled: true,
                            //gestureRecognizers: ,
                            // 마커와 내 반경 설정
                            markers:
                                selectedAreaMarker, //Set.from([curLocMarker],),
                            circles: Set.from([myAreaCircle]),

                            // controller setting
                            onMapCreated: _onMapCreated),
                      ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      //const Text("내 관심 경작지 리스트(combo box)"),

                      Text(searchedAddress),

                      Text("관심 지역까지 거리 : ${distance1.toStringAsFixed(2)} km"),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              // google map 이동
                              // Get.toNamed("/MyAreaList");

                              _showMyAreaActionSheet();
                            },
                            child: Text("내 경작지 보기"),
                          ),
                          SizedBox(
                            width: 20,
                          ),
                          ElevatedButton(
                            onPressed: () {
                              // 관심농지 추가 하여 마커 색이 변한다.
                              _addMyAreaDialog();
                            },
                            child: Text("관심농지로 추가"),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ],
            );
          } // If end
          // 권한 설정이 안되어있을 때
          return Center(
            child: Text(
              snapshot.data.toString(),
            ),
          );
        },
      ),
      floatingActionButton: Stack(
        children: <Widget>[
          Positioned(
            top: 520,
            right: -0,
            child: FloatingActionButton(
              
              onPressed: () {
            
                _floatCurPos() async {
                  var floatingCurPos = await Geolocator.getCurrentPosition();
                  mapController.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target:
                            LatLng(floatingCurPos.latitude, floatingCurPos.longitude),
                        zoom: 14.4746,
                      ),
                    ),
                  );
                }
                _floatCurPos();
            
                setState(() {});
              },
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.navigation),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Functions

  //2024.04.24 update

  _predictAction(areaSize, myareaLat, myareaLng) async {
    //double areaSize = 0;
    //areaSize = double.parse(areaController.text);
    print('predict : $myareaLat');
    print('predict : $myareaLng');
    double nearLat = 0;
    nearLat = await nearLatLng(latlong.LatLng(myareaLat, myareaLng));
    
    print("예측시작");
    print('predictAction nearLat : $nearLat');

    var url = Uri.parse(
        'http://192.168.50.69:8080/predict?areaSize=${areaSize}&lat=$myareaLat&lng=$myareaLng&nearLat=$nearLat');
    print(url);
    var response = await http.readBytes(url);
    double result = json.decode(utf8.decode(response));

//    print("11");
    Get.defaultDialog(
        title: '결과',
        middleText:
            //"서버점검중입니다 \n 09:00~23:00", 
            '예상 수확량은 ${result.toStringAsFixed(2)}톤 입니다.\n',
        actions: [
          ElevatedButton(onPressed: () => Get.back(), child: const Text('확인'))
        ]);

    //print(result.toString());
  }

  _longTapSelectPosition(LatLng longTapPostion) {
    longTapCounter++;
    // 마커 추가
    Marker newMarker = Marker(
      markerId: MarkerId(longTapPostion.toString()),
      position: longTapPostion,
      infoWindow: InfoWindow(title: '관심소재지'),
      icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueBlue), // 마커 아이콘 설정
    );
    // map 이동
    mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: longTapPostion,
          zoom: 14.4746,
        ),
      ),
    );

    // 마커 세트 업데이트
    selectedAreaMarker.add(newMarker);
    setState(() {});
    // 소재지 정보 업데이트
    getPlaceAddress(longTapPostion.latitude, longTapPostion.longitude);
  }

  // 2024.04.23 updated
  _showBottomSheetForInput() {
    // Desc : 관심 농작품과 재배면적 을 받는 bottom sheet
    // Date : 2024.04.24
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.5,
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: myareaProductTFcontroller,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(labelText: "관심작물 이름"),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: myareaSizeTFcontroller,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(labelText: "재배지 면적 (제곱미터)"),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        // DB insert code
                        _insertMyArea(
                            interestLoc.latitude, interestLoc.longitude);
                        myareaMarkerList.add(findMarker);
                        // Get.defaultDialog(
                        //   middleText: "저장되었습니다.",
                        //   actions: [
                        //     ElevatedButton(
                        //       onPressed: ()=>Get.back(),
                        //       child: Text("ok"))
                        //   ]

                        // );

                        Get.back();
                      },
                      child: const Text("저장 "),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Get.back();
                      },
                      child: const Text("취소 "),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 2024.04.23 Updated beloow

  _basicMarkershow() {
    List for_add = List.generate(myareaData.length, (index) {
      Marker(
          markerId: const MarkerId("현재위치"),
          position: LatLng(
              myareaData[index]['area_lat'], myareaData[index]['area_lng']),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: const InfoWindow(
            title: "현재위치 ",
            snippet: "",
          ));
    });
    selectedAreaMarker = (Set.from(for_add));
  }

  _insertMyArea(curLat, curLng) async {
    // Desc : 내관심 소재지 mySQL DB 에서 정보 가져오는 함수
    // Update : 2024.04.22 by pdg
    //  - 더조은 학원 IP address  :  192.168.50.69
    //
    //userId=pulpilisory&area_lat=37.108436612&area_lng=127.22501390&area_size=1200&area_product=배추&area_address=안성시 양선면 난실리
    myareaProduct = myareaProductTFcontroller.text.trim().toString();
    String databaseIP = "192.168.50.69";
    String urlAreaInfo =
        "&area_lat=$curLat&area_lng=$curLng&area_size=$myAreaMeterSquare&area_product=$myareaProduct&area_address=$myareaAddress";
    String urlAddress = "http://$databaseIP:8080/myareaInsert?userId=$userId";
    urlAddress += urlAreaInfo;
    print(urlAddress);
    var url = Uri.parse(urlAddress);
    var response = await http.get(url);
    //print(response.body);
    //var dataConvertedJSON = json.decode(utf8.decode(response.bodyBytes));
    //List result = dataConvertedJSON;
    //myareaData.addAll(result);

    // markers 추가 하기
    selectedAreaMarker.add(Marker(
      markerId: MarkerId(myareaProduct),
      position: LatLng(curLat, curLng),
      infoWindow: InfoWindow(title: '관심소재지'),
      icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure), // 마커 아이콘 설정
    ));

    setState(() {});
  }

  _getUserIdFromSharedPref() async {
    // Desc : user Id 를 받아옴 .
    // Update : 2024.04.23 by pdg
    prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('userId') ?? ""; // 기본값은 빈 문자열
    //print(" userID : $userId");
    _getMyareaJSONData();
  }

  // 2024.04.22 Udated bellow
  // 내 소재지 정보 불러오는 함수 .

  _getMyareaJSONData() async {
    // Desc : 내관심 소재지 mySQL DB 에서 정보 가져오는 함수
    // Update : 2024.04.22 by pdg
    //  - 더조은 학원 IP address  :  192.168.50.69    String url_address = "http://localhost:8080/myarea?userId=$userId";

    String ip_database = "192.168.50.69";
    String url_address = "http://$ip_database:8080/myarea?userId=$userId";
    var url = Uri.parse(url_address);
    var response = await http.get(url);
    //print("나의 경작지 정보 받아옴 : userId : $userId");
    //print(url);
    //print(response.body);
    var dataConvertedJSON = json.decode(utf8.decode(response.bodyBytes));
    List result = dataConvertedJSON;
    myareaData = [];
    myareaData.addAll(result);
    setState(() {});
  }

  _showMyAreaActionSheet() {
    // 이미 열려 있는 엑션 시트가 있는지 확인하고 있다면 닫기
    List<Widget> myarea_view = List.empty();
    print(myareaData.length);
    _getMyareaJSONData();
    myarea_view = List.generate(
      myareaData.length,
      (index) => Slidable(
        startActionPane: ActionPane(
          motion: const BehindMotion(),
          children: [
            SlidableAction(
              spacing: 1,
              backgroundColor: const Color.fromARGB(255, 75, 152, 214),
              icon: Icons.edit,
              label: "수정",
              onPressed: (context) {
                Get.defaultDialog(
                  content: MyAreaEdit(
                      myareaSize: myareaData[index]['area_size'],
                      myareaProduct: myareaData[index]['area_product']),
                );
                print("수정 슬라이드 ");
              },
            )
          ],
        ),
        endActionPane: ActionPane(
          motion: StretchMotion(),
          children: [
            SlidableAction(
              onPressed: (context) {},
              backgroundColor: const Color.fromARGB(255, 211, 94, 86),
              icon: Icons.edit,
              label: "삭제",
            )
          ],
        ),
        child: CupertinoActionSheetAction(
          onPressed: () {
            print("clicked");
            // 해당 위치로 이동하기
            _gotoSelectedLoc(index);
            Get.back();
          },
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${index + 1} . ${myareaData[index]['area_address']}(${myareaData[index]['area_product']})'
                              .length >
                          20
                      ? '${index + 1} . ${myareaData[index]['area_address']}(${myareaData[index]['area_product']})'
                              .substring(0, 20) +
                          "..."
                      : '${index + 1} . ${myareaData[index]['area_address']}(${myareaData[index]['area_product']})',
                  style: TextStyle(fontSize: 15),
                ),
                SizedBox(
                  width: 120,
                  child: ElevatedButton(
                    onPressed: () {
                      // 생산량 예측 함수
                      _predictAction(
                        myareaData[index]['area_size'],
                        myareaData[index]['area_lat'],
                        myareaData[index]['area_lng'],
                      );
                    },
                    child: const Text(
                      "생산량 예측하기",
                      style: TextStyle(fontSize: 20),
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );

    showCupertinoModalPopup(
      semanticsDismissible: true,
      context: context,
      builder: (context) {
        return GestureDetector(
            child: GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: CupertinoActionSheet(
              messageScrollController: ScrollController(),
              message: SingleChildScrollView(
                controller: ScrollController(),
                child: Column(
                    //children: [],
                    ),
              ),
              title: const Text("내 경작지 리스트"),
              actions: myarea_view),
        ));

        //MyAreaList();
      },
      barrierDismissible: true,
    );
  }

  _gotoSelectedLoc(index) {
    // Desc : 내 경작지 리스트에서 클릭한 항목에 대한 주소로 구글맵 이동
    // Update : 2024.04.23 by pdg
    print(
        "${myareaData[index]['area_address']}(${myareaData[index]['area_product']})");
    mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(
              myareaData[index]['area_lat'], myareaData[index]['area_lng']),
          zoom: 14.4746,
        ),
      ),
    );
  }

  _addMyAreaDialog() {
    // Desc : 현재 위치를 관심 소재지로 추가하는 함수
    // Date : 2024.04.24 by pdg
    Get.defaultDialog(
      barrierDismissible: true,
      title: "관심소재지 등록",
      middleText: " $searchedAddress 관심 소재지로 등록하시겠습니까?",
      actions: [
        ElevatedButton(
          onPressed: () {
            // 관심작물과 재배면적 입력 함수 호출
            Get.back();
            _showBottomSheetForInput();
          },
          child: Text("예"),
        ),
        SizedBox(width: 10,),
        ElevatedButton(onPressed: () => Get.back(), child: Text("아니오")),
      ],
    );
  }

  // 2024.04.21 Updated Below
  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  _curLocAddressGet() async {
    // Desc : 현재 위치의 주소 정보를 가져오는 함수
    // Date : 2024.04.24 by pdg
    //  - Curposition 에서 위치를 검색하여 소재지 주소를 받아온다 . => search_address 에 업데이트 한다 .
    var curPosition = await Geolocator.getCurrentPosition();

    var findAddressUri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${curPosition.latitude},${curPosition.longitude}&language=ko&key=AIzaSyDslR-okT6JXHWhMmrOXaNxXhA6C0LxJHo');

    var responseFAU = await http.get(findAddressUri);
    // Json 확인
    //print(responseFAU.body)
    // Json data convert
    var dataCovertedJSON = json.decode(utf8.decode(responseFAU.bodyBytes));

    List address_result = dataCovertedJSON['results'];
    // Formatted address 를 업데이트
    searchedAddress = address_result[0]['formatted_address'];
    setState(() {});
  }

  searchPlace() async {
    String textsearchUrl =
        "https://maps.googleapis.com/maps/api/place/textsearch/json?query=";
    String key = "AIzaSyDslR-okT6JXHWhMmrOXaNxXhA6C0LxJHo";
    textsearchUrl += "${locationTfController.text}&language=ko&key=$key";
    var findAddressUri = Uri.parse(textsearchUrl);
    var responsePlace = await http.get(findAddressUri);
    //print(responsePlace.body);
    var dataCovertedJSON = json.decode(utf8.decode(responsePlace.bodyBytes));
    List address_result = dataCovertedJSON['results'];
    // result
    searchedAddress = address_result[0]['formatted_address'];

    // interstLco 에 현재 위치 위도 경도 넣기
    interestLoc = LatLng(address_result[0]['geometry']['location']['lat'],
        address_result[0]['geometry']['location']['lng']);

    // map 이동
    mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: interestLoc,
          zoom: 14.4746,
        ),
      ),
    );

    // 검색한 소재지의 marker 생성 (findmarker )
    findMarker = Marker(
      markerId: MarkerId(searchedAddress),
      position: interestLoc,
    );
    // markers 에 추가

    markers.add(findMarker);
    // 거리계산
    _curPosGenCalcDistance();
    // 내 위치 에 해당 위치 변수 넣어주기
    myareaAddress = searchedAddress;
    setState(() {});
  }

  // 내가 입력한 주소의 위도경도를 아웃풋.
  getPlaceAddress(double lat, double lng) async {
    // Desc : 위도와 경도를 입력받아서 소재지의 주소 변수를 업데이트함.
    // Date :  2024.04.21
    //
    var findAddressUri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&language=ko&key=AIzaSyDslR-okT6JXHWhMmrOXaNxXhA6C0LxJHo');

    var responseFAU = await http.get(findAddressUri);
    // Json 확인
    //print(responseFAU.body)
    // Json data convert
    var dataCovertedJSON = json.decode(utf8.decode(responseFAU.bodyBytes));

    List address_result = dataCovertedJSON['results'];
    // Formatted address 를 업데이트
    searchedAddress = address_result[0]['formatted_address'];
    //print(address_result);
    // 검색한 주소로 맵의 위치가 이동하면서 관심 지역 위도 경도 변수가 업데이트 된다.
    interestLoc = LatLng(address_result[0]['geometry']['location']['lat'],
        address_result[0]['geometry']['location']['lng']);
    // data.addAll(result);
    // 나의 주소 <- 검색한주소 : 변경 필요
    myareaAddress = searchedAddress;
    setState(() {});
    //return searchedAddress;
  }

  _curPositiongGet() async {
    // Desc : 현재위치 받아 업데이트 하는 함수
    // Date : 2024.04.24  by pdg
    currentLocGetCallCount++;
    if (currentLocGetCallCount < 5) {
      var curPosition = await Geolocator.getCurrentPosition();
      curLoc = LatLng(curPosition.latitude, curPosition.longitude);

      // 현재위치 주소 가져오는 함수 실행

      // 현재위치 주소 에대한 마커 설정
      curLocMarker = Marker(
          markerId: const MarkerId("현재위치"),
          position: curLoc!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: const InfoWindow(
            title: "현재위치 ",
            snippet: "",
          ));
      print(" 현재위치가 설정되었습니다 ");

      var findAddressUri = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=${curPosition.latitude},${curPosition.longitude}&language=ko&key=AIzaSyDslR-okT6JXHWhMmrOXaNxXhA6C0LxJHo');

      var responseFAU = await http.get(findAddressUri);
      // Json 확인
      //print(responseFAU.body)
      // Json data convert
      setState(() {
        var dataCovertedJSON = json.decode(utf8.decode(responseFAU.bodyBytes));

        List address_result = dataCovertedJSON['results'];
        // Formatted address 를 업데이트
        searchedAddress = address_result[0]['formatted_address'];
        //print(address_result);
        // 검색한 주소로 맵의 위치가 이동하면서 관심 지역 위도 경도 변수가 업데이트 된다.
        interestLoc = LatLng(address_result[0]['geometry']['location']['lat'],
            address_result[0]['geometry']['location']['lng']);
        // data.addAll(result);
        // 나의 주소 <- 검색한주소 : 변경 필요
        myareaAddress = searchedAddress;
      });
    }
  }

  _curPosGenCalcDistance() async {
    // Desc : 내 위치와 관심 경작지 위치의 거리 계산 함수
    // Date : 2024.04.24 by pdg
    // 현재 위치 파악
    var curPosition = await Geolocator.getCurrentPosition();
    // 내 관심경작지와의 거리 파악
    distance1 = Geolocator.distanceBetween(
            curPosition.latitude,
            curPosition.longitude,
            interestLoc.latitude,
            interestLoc.longitude) /
        1000.0;
    setState(() {});
  }

  // 내위치  파악 및 권한 설정 함수
  Future<String> checkPermission() async {
    islocationEnable = await Geolocator.isLocationServiceEnabled();

    if (!islocationEnable) {
      return "위치 서비스를 활성화 해주세요.";
    }
    // 위치 권한 확인
    LocationPermission checkedPermission = await Geolocator.checkPermission();

    if (checkedPermission == LocationPermission.denied) {
      // 권한 요청
      checkedPermission = await Geolocator.requestPermission();
      if (checkedPermission == LocationPermission.denied) {
        return "위치 권한을 허가해주세요";
      }
    }
    // 위치 권한 거절됨 ( 앱에서 재요청 불가 )
    if (checkedPermission == LocationPermission.deniedForever) {
      return "앱의 위치 권한을 설정에서 허가해주세요.";
    }

    // 위의 모든 조건이 통과되면 위치 권한 허가 가 완료 된것임.
    return "위치 권한이 허가 되었습니다.";
  }


  
  nearLatLng(latlong.LatLng originalLatLng) {
    // 위치 List
    List<Map> placeListLocation = [
    { 'lat' : 37.2343060386837, 'lng' : 127.201357139725,}, // '경기도 용인시 처인구',
    { 'lat' : 36.3622851114392, 'lng' : 127.356257593324,}, // '대전광역시 유성구',
    { 'lat' : 36.8153571576607, 'lng' : 127.786652163107,}, //  '충청북도 괴산군',
    { 'lat' : 36.9910490160221, 'lng' : 127.925961035784,}, // '충청북도 충주시',
    { 'lat' : 36.855378991826, 'lng' : 127.435536085976,}, // '충청북도 진천군',
    { 'lat' : 35.5698491739949, 'lng' : 126.8560,}, // '전라북도 정읍시',
    { 'lat' : 35.7316577924649, 'lng' : 126.7330,}, //  '전라북도 부안군',
    { 'lat' : 34.6420615268858, 'lng' : 126.7672,}, //  '전라남도 강진군',
    { 'lat' : 34.486828620348, 'lng' : 126.2634,}, // '전라남도 진도군',
    { 'lat' : 34.5735165884839, 'lng' : 126.5993,}, //  '전라남도 해남군',
    { 'lat' : 36.0437417308541, 'lng' : 129.3686,}, //  '경상북도 포항시 북구',
    { 'lat' : 36.4150618798074, 'lng' : 129.3653,}, // '경상북도 영덕군',
    { 'lat' : 36.6667028574142, 'lng' : 129.1125,}, // '경상북도 영양군',
    { 'lat' : 35.2285653558628, 'lng' : 128.8894,}, // '경상남도 김해시',
    { 'lat' : 34.8544448244005, 'lng' : 128.4331,}, //  '경상남도 통영시',
  ];
    // 가장 가까운 위치의 위도
    double nearLat = 0;
    
    latlong.Haversine haverCalc = const latlong.Haversine();

    // 초기값 : 단순히 첫번쨰의 값으로 비교하여 넣음
    double nearDistance = haverCalc.distance(originalLatLng, latlong.LatLng(placeListLocation[0]['lat'], placeListLocation[0]['lng']));
    nearLat = placeListLocation[0]['lat'];
    // --------

    // for문을 통해 최소값 확인
    for(int j=0; j<placeListLocation.length; j++) {
      if(nearDistance > haverCalc.distance(originalLatLng, latlong.LatLng(placeListLocation[j]['lat'], placeListLocation[j]['lng']))) {
        // 최솟값일때, 비교를 위해 값들을 따로 저장
        nearDistance = haverCalc.distance(originalLatLng, latlong.LatLng(placeListLocation[j]['lat'], placeListLocation[j]['lng']));
        nearLat = placeListLocation[j]['lat'];
      }
    }
    return nearLat;
  }

} // END
