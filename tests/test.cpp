#include <gtest/gtest.h>
#include <string>
#include <fstream>
#include <streambuf>
#include <cstdlib>
#include <cstdio>
#include <algorithm>

void runRefactorTest(const std::string& inputFile, const std::string& goldFile) {
    std::string tempFile = "temp_test_file.cpp";
    std::ifstream src(inputFile, std::ios::binary);
    ASSERT_TRUE(src.is_open()) << "Не удалось открыть входной файл: " << inputFile;
    std::ofstream dst(tempFile, std::ios::binary);
    dst << src.rdbuf();
    src.close();
    dst.close();

    std::string command = "./refactor_tool " + tempFile + " --"; 
    
    int result = system(command.c_str());
    ASSERT_EQ(result, 0) << "Утилита refactor_tool завершилась с ошибкой.";

    std::ifstream modifiedStream(tempFile);
    std::string modifiedContent((std::istreambuf_iterator<char>(modifiedStream)),
                                 std::istreambuf_iterator<char>());

    std::ifstream goldStream(goldFile);
    ASSERT_TRUE(goldStream.is_open()) << "Не удалось открыть золотой файл: " << goldFile;
    std::string goldContent((std::istreambuf_iterator<char>(goldStream)),
                            std::istreambuf_iterator<char>());

                            
    modifiedContent.erase(std::remove(modifiedContent.begin(), modifiedContent.end(), '\r'), modifiedContent.end());
    goldContent.erase(std::remove(goldContent.begin(), goldContent.end(), '\r'), goldContent.end());
                            
    ASSERT_EQ(modifiedContent, goldContent);

    remove(tempFile.c_str());
}

TEST(RefactoringTests, AddsVirtualToDestructors) {
    runRefactorTest("../tests/tests_data/test1.cpp", 
                    "../tests/tests_data/test1_ref.cpp");
}

TEST(RefactoringTests, AddsOverrideToMethods) {
    runRefactorTest("../tests/tests_data/test2.cpp", 
                    "../tests/tests_data/test2_ref.cpp");
}

TEST(RefactoringTests, AddsReferenceToRangeFor) {
    runRefactorTest("../tests/tests_data/test3.cpp", 
                    "../tests/tests_data/test3_ref.cpp");
}